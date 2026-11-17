import Foundation
import JavaScriptCore

// Unit tests for Bridge.swift and Turns.swift. Run with ./test.sh (compiles for macOS, no device needed).

var failures = 0
var count = 0
func check(_ cond: @autoclosure () -> Bool, _ name: String, file: String = #file, line: Int = #line) {
    count += 1
    if !cond() { failures += 1; print("FAIL \(name)  (\((file as NSString).lastPathComponent):\(line))") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ name: String, line: Int = #line) {
    count += 1
    if a != b { failures += 1; print("FAIL \(name): got \(a), expected \(b)  (line \(line))") }
}

/// Runs a JS expression in JavaScriptCore so string-literal tests check real JS parsing, not our assumptions.
func jsEval(_ src: String) -> String? { JSContext()?.evaluateScript(src)?.toString() }

// MARK: - WorldMessage.parse

eq(WorldMessage.parse(["type": "ready"]), .ready, "ready")
eq(WorldMessage.parse(["type": "askTapped"]), .askTapped, "askTapped")
eq(WorldMessage.parse(["type": "askClosed"]), .askClosed, "askClosed")
eq(WorldMessage.parse(["type": "ask", "text": "how do I rebase"]), .ask(text: "how do I rebase"), "ask")
eq(WorldMessage.parse(["type": "ask", "text": "  padded \n"]), .ask(text: "padded"), "ask trims whitespace")
eq(WorldMessage.parse(["type": "ask", "text": "   "]), nil, "ask whitespace-only is ignored")
eq(WorldMessage.parse(["type": "ask", "text": ""]), nil, "ask empty is ignored")
eq(WorldMessage.parse(["type": "ask"]), nil, "ask without text is ignored")
eq(WorldMessage.parse(["type": "ask", "text": 42]), nil, "ask with non-string text is ignored")
let long = String(repeating: "a", count: 2000)
eq(WorldMessage.parse(["type": "ask", "text": long]), .ask(text: String(repeating: "a", count: WorldMessage.maxQuestionLength)), "ask is capped")
eq(WorldMessage.parse(["type": "dance"]), nil, "unknown type is ignored")
eq(WorldMessage.parse(["kind": "ready"]), nil, "missing type is ignored")
eq(WorldMessage.parse(["type": 1]), nil, "non-string type is ignored")
eq(WorldMessage.parse("ready"), nil, "non-dictionary body is ignored")
eq(WorldMessage.parse(NSNull()), nil, "null body is ignored")
eq(WorldMessage.parse(["type": "ask", "text": "emoji 🤖 ok"]), .ask(text: "emoji 🤖 ok"), "unicode survives")

// MARK: - jsStringLiteral (round-trip through a real JS engine)

let nasty = [
    "plain", "", "quote \" and 'single'", "back\\slash", "new\nline\ttab\r",
    "</script><script>alert(1)</script>", "line\u{2028}sep\u{2029}para", "emoji 🤖", "nul\u{0}byte",
    "${template}", "`backtick`"
]
for s in nasty {
    let lit = jsStringLiteral(s)
    eq(jsEval(lit), s, "JS round-trip of \(s.debugDescription)")
    check(!lit.contains("</"), "no raw </ in literal for \(s.debugDescription)")
    check(!lit.contains("\u{2028}") && !lit.contains("\u{2029}"), "no raw line separators for \(s.debugDescription)")
}

// MARK: - WorldCommand.javaScript

eq(WorldCommand.setMood(.sleepy).javaScript, "window.byte.setMood(\"sleepy\")", "setMood")
eq(WorldCommand.setMood(.night).javaScript, "window.byte.setMood(\"night\")", "setMood night owl id")
eq(WorldCommand.setVoiceState(.thinking).javaScript, "window.byte.setVoiceState(\"thinking\")", "setVoiceState")
eq(WorldCommand.say("Hi \"you\"").javaScript, "window.byte.say(\"Hi \\\"you\\\"\")", "say escapes")
eq(WorldCommand.celebrate.javaScript, "window.byte.celebrate()", "celebrate")
eq(WorldCommand.setLevel(0.6).javaScript, "window.byte.setLevel(0.6)", "setLevel")
eq(WorldCommand.setLevel(5).javaScript, "window.byte.setLevel(1.0)", "setLevel clamps high")
eq(WorldCommand.setLevel(-2).javaScript, "window.byte.setLevel(0.0)", "setLevel clamps low")
eq(WorldCommand.setLevel(.nan).javaScript, "window.byte.setLevel(0.0)", "setLevel NaN -> 0")
eq(WorldCommand.setLevel(.infinity).javaScript, "window.byte.setLevel(0.0)", "setLevel inf -> 0")
// Swift enums must match the ids main.js accepts
eq(Mood.allCases.map(\.rawValue), ["happy", "focused", "sleepy", "bored", "night", "celebrating"], "mood ids match main.js")
eq(VoiceState.allCases.map(\.rawValue), ["idle", "listening", "thinking", "speaking"], "voice states match main.js")

// MARK: - WorldBridge queueing

do {
    var out: [String] = []
    let b = WorldBridge { out.append($0) }
    b.send(.celebrate); b.send(.say("a"))
    eq(out, [], "nothing evaluated before ready")
    eq(b.pending.count, 2, "commands queued before ready")
    b.markReady()
    eq(out, ["window.byte.celebrate()", "window.byte.say(\"a\")"], "queue flushed in order on ready")
    eq(b.pending.count, 0, "queue empty after flush")
    b.send(.say("b"))
    eq(out.last, "window.byte.say(\"b\")", "sent immediately when ready")
    b.markNotReady(); b.send(.say("c"))
    eq(out.count, 3, "queues again after markNotReady")
    b.markReady()
    eq(out.last, "window.byte.say(\"c\")", "flushes after re-ready")
}
do {
    var out: [String] = []
    let b = WorldBridge { out.append($0) }
    for i in 0..<(WorldBridge.maxPending + 5) { b.send(.say("\(i)")) }
    eq(b.pending.count, WorldBridge.maxPending, "queue is bounded")
    b.markReady()
    eq(out.first, "window.byte.say(\"5\")", "oldest commands dropped first")
    eq(out.last, "window.byte.say(\"\(WorldBridge.maxPending + 4)\")", "newest command kept")
}

// MARK: - TurnController (with a scripted brain)

final class ScriptedBrain: Brain {
    final class Handle: Cancellable { var cancelled = false; func cancel() { cancelled = true } }
    var calls: [(question: String, mood: Mood, history: [Exchange], onText: (String) -> Void, completion: (Result<String, Error>) -> Void, handle: Handle)] = []
    func answer(question: String, mood: Mood, history: [Exchange], onText: @escaping (String) -> Void,
                completion: @escaping (Result<String, Error>) -> Void) -> Cancellable {
        let h = Handle(); calls.append((question, mood, history, onText, completion, h)); return h
    }
}
struct ScriptedError: Error {}

func makeTurns() -> (TurnController, ScriptedBrain, () -> [String]) {
    var out: [String] = []
    let bridge = WorldBridge { out.append($0) }
    let brain = ScriptedBrain()
    let turns = TurnController(bridge: bridge, brain: brain)
    turns.handle(.ready)
    return (turns, brain, { out })
}

do { // happy path
    let (turns, brain, out) = makeTurns()
    turns.handle(.ask(text: "q1"))
    eq(out(), ["window.byte.setVoiceState(\"thinking\")"], "ask -> thinking")
    eq(brain.calls.count, 1, "brain asked once"); eq(brain.calls[0].question, "q1", "question passed through")
    eq(brain.calls[0].mood, .happy, "default mood passed")
    brain.calls[0].onText("Try")
    brain.calls[0].onText("Try git")
    brain.calls[0].completion(.success("Try git rebase."))
    eq(out(), ["window.byte.setVoiceState(\"thinking\")", "window.byte.setVoiceState(\"speaking\")",
               "window.byte.say(\"Try\")", "window.byte.say(\"Try git\")", "window.byte.say(\"Try git rebase.\")"],
       "thinking -> speaking once -> text so far")
}
do { // mood reaches the brain
    let (turns, brain, _) = makeTurns()
    turns.mood = .sleepy
    turns.handle(.ask(text: "q"))
    eq(brain.calls[0].mood, .sleepy, "current mood passed to brain")
}
do { // answer with no streamed text still speaks
    let (turns, brain, out) = makeTurns()
    turns.handle(.ask(text: "q"))
    brain.calls[0].completion(.success("Done."))
    eq(Array(out().suffix(2)), ["window.byte.setVoiceState(\"speaking\")", "window.byte.say(\"Done.\")"], "completion-only answer")
}
do { // brain failure
    let (turns, brain, out) = makeTurns()
    turns.handle(.ask(text: "q"))
    brain.calls[0].onText("Half an ans")
    brain.calls[0].completion(.failure(ScriptedError()))
    eq(out().last, "window.byte.say(\(jsStringLiteral(TurnController.dozedOffText)))", "failure says it dozed off")
    eq(out().filter { $0.contains("speaking") }.count, 1, "speaking sent once even on failure")
}
do { // close mid-answer
    let (turns, brain, out) = makeTurns()
    turns.handle(.ask(text: "q"))
    brain.calls[0].onText("Partial")
    turns.handle(.askClosed)
    check(brain.calls[0].handle.cancelled, "askClosed cancels the brain")
    let n = out().count
    brain.calls[0].onText("Partial late")
    brain.calls[0].completion(.success("late"))
    eq(out().count, n, "late callbacks after close are ignored")
}
do { // second question while first is streaming
    let (turns, brain, out) = makeTurns()
    turns.handle(.ask(text: "first"))
    brain.calls[0].onText("First ans")
    turns.handle(.ask(text: "second"))
    check(brain.calls[0].handle.cancelled, "new question cancels the old one")
    eq(out().last, "window.byte.setVoiceState(\"thinking\")", "new question goes back to thinking")
    brain.calls[0].onText("First ans late")
    check(!out().contains("window.byte.say(\"First ans late\")"), "old answer can't leak into new turn")
    brain.calls[1].onText("Second")
    eq(Array(out().suffix(2)), ["window.byte.setVoiceState(\"speaking\")", "window.byte.say(\"Second\")"], "second turn speaks again")
}
do { // reset (web content reload)
    let (turns, brain, out) = makeTurns()
    turns.handle(.ask(text: "q"))
    turns.reset()
    check(brain.calls[0].handle.cancelled, "reset cancels the brain")
    let n = out().count
    brain.calls[0].completion(.success("late"))
    eq(out().count, n, "callbacks after reset are ignored")
}
do { // askClosed / askTapped with nothing in flight are harmless
    let (turns, brain, out) = makeTurns()
    turns.handle(.askClosed); turns.handle(.askTapped)
    eq(out(), [], "no commands for idle close/tap"); eq(brain.calls.count, 0, "brain not called")
}
do { // ask before ready: commands queue, then flush on ready
    var out: [String] = []
    let bridge = WorldBridge { out.append($0) }
    let brain = ScriptedBrain()
    let turns = TurnController(bridge: bridge, brain: brain)
    turns.handle(.ask(text: "early"))
    eq(out, [], "nothing evaluated before ready")
    turns.handle(.ready)
    eq(out, ["window.byte.setVoiceState(\"thinking\")"], "queued thinking flushed on ready")
}

// MARK: - Conversation memory (decision 2026-11-17, 3A)

do {
    let (turns, brain, _) = makeTurns()
    func ask(_ q: String, answer: String?) {
        turns.handle(.ask(text: q))
        if let a = answer { brain.calls.last!.completion(.success(a)) }
    }
    ask("q1", answer: "a1")
    eq(brain.calls[0].history, [], "first question has no history")
    ask("q2", answer: "a2")
    eq(brain.calls[1].history, [Exchange(question: "q1", answer: "a1")], "second question hears the first")
    ask("q3", answer: "a3")
    eq(brain.calls[2].history, [Exchange(question: "q1", answer: "a1"), Exchange(question: "q2", answer: "a2")], "two remembered")
    ask("q4", answer: nil)
    eq(brain.calls[3].history, [Exchange(question: "q2", answer: "a2"), Exchange(question: "q3", answer: "a3")],
       "only the last \(TurnController.historyLimit) are sent, oldest dropped")
    turns.handle(.ask(text: "q5"))  // replaces q4 mid-answer
    brain.calls[3].completion(.success("late a4"))
    eq(turns.history.map(\.question), ["q2", "q3"], "a cut-off answer is not remembered")
    brain.calls[4].completion(.failure(ScriptedError()))
    eq(turns.history.map(\.question), ["q2", "q3"], "a failed answer (dozed off) is not remembered")
    ask("q6", answer: "a6")
    eq(turns.history.map(\.question), ["q3", "q6"], "history keeps rolling")
    turns.handle(.askClosed)
    eq(turns.history, [], "closing the bubble forgets the conversation")
    ask("q7", answer: "a7")
    eq(brain.calls.last!.history, [], "next bubble starts fresh")
}
do { // commands: an unknown place keeps the conversation, an acted-out command ends it
    let clock = { () -> (TurnController, ScriptedBrain, () -> Void) in
        var jobs: [() -> Void] = []
        let bridge = WorldBridge { _ in }; bridge.markReady()
        let brain = ScriptedBrain()
        let t = TurnController(bridge: bridge, brain: brain, schedule: { _, w in jobs.append(w) })
        return (t, brain, { let j = jobs; jobs = []; j.forEach { $0() } })
    }
    let (turns, brain, fire) = clock()
    turns.handle(.ask(text: "q1")); brain.calls[0].completion(.success("a1"))
    turns.handle(.ask(text: "go to the kitchen"))
    eq(turns.history.count, 1, "unknown place keeps the conversation (bubble stays open)")
    turns.handle(.ask(text: "q2"))
    eq(brain.calls[1].history.map(\.question), ["q1"], "conversation continues after an unknown place")
    brain.calls[1].completion(.success("a2"))
    turns.handle(.ask(text: "jump")); fire()
    eq(turns.history, [], "an acted-out command closes the bubble and forgets")
    turns.handle(.ask(text: "q3")); brain.calls.last!.completion(.success("a3"))
    eq(turns.history.count, 1, "remembering again after the command")
    turns.reset()
    eq(turns.history, [], "world reload forgets")
}

// MARK: - Commands (see CommandsTests.swift)

runCommandsTests()

// MARK: - Push events (see EventsTests.swift)

runEventsTests()

// MARK: - LlamaBrain (see LlamaBrainTests.swift)

runLlamaBrainTests()

print(failures == 0 ? "OK: \(count) checks passed" : "\(failures) of \(count) checks FAILED")
exit(failures == 0 ? 0 : 1)

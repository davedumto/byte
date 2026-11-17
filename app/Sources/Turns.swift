import Foundation

// One question-and-answer turn: world message in, brain answer streamed back into the bubble.
// Foundation only, so it can be unit-tested on the Mac.

protocol Cancellable {
    func cancel()
}

/// One earlier question and its finished answer, sent along so follow-ups make sense
/// ("and how do I undo that?"). Kept in memory only, never written to disk or logged.
struct Exchange: Equatable {
    let question: String
    let answer: String
}

/// Anything that can answer a question (LlamaBrain in the app, a scripted fake in tests).
/// Contract: callbacks arrive on the main queue; `onText` gets the full answer so far (not a delta);
/// after `cancel()` no further callbacks are made. `history` is oldest first.
protocol Brain: AnyObject {
    func answer(question: String,
                mood: Mood,
                history: [Exchange],
                onText: @escaping (String) -> Void,
                completion: @escaping (Result<String, Error>) -> Void) -> Cancellable
}

/// Drives the world through Thinking -> Speaking for each typed question, or acts out a typed command
/// (Commands.swift) without calling the brain. Main-queue only.
final class TurnController {
    /// Said when the brain fails (spec risk table: "says it dozed off").
    static let dozedOffText = "Sorry, I dozed off. Ask me again?"
    /// How long a command's reply stays in the bubble before the bubble closes and Byte acts.
    static let commandDelay: TimeInterval = 1.2
    /// Exchanges remembered while the bubble stays open (decision 2026-11-17, 3A). Context budget, 1,024 tokens:
    /// system prompt ~60 + 3 questions of up to 500 chars (~125 tokens each) + 2 answers of up to 80 tokens
    /// + the 80-token reply leaves ~350 tokens spare.
    static let historyLimit = 2

    private let bridge: WorldBridge
    private let brain: Brain
    private let log: (String) -> Void
    var mood: Mood = .happy   // v1 has no mood engine yet; the world starts happy

    private var turnID = 0                 // bumps on every new turn or cancel; stale callbacks compare against it
    private var inFlight: Cancellable?
    private var speaking = false
    private var pendingAction: WorldAction?   // a command waiting out commandDelay
    /// The conversation in the open bubble. Cleared when the bubble closes, when a command moves Byte
    /// (that closes the bubble too), and when the world reloads; the app never saves it.
    private(set) var history: [Exchange] = []
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(bridge: WorldBridge, brain: Brain, log: @escaping (String) -> Void = { _ in },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.bridge = bridge
        self.brain = brain
        self.log = log
        self.schedule = schedule
    }

    func handle(_ message: WorldMessage) {
        switch message {
        case .ready:
            bridge.markReady()
        case .askTapped:
            // v1: the world already shows the ask bubble and text field. v2 starts a voice turn here.
            log("askTapped")
        case .ask(let text):
            if let command = CommandMatcher.match(text) { startCommand(command) } else { startTurn(question: text) }
        case .askClosed:
            // The world has already returned itself to idle; drop the answer. A command still waiting
            // to be acted out runs now: closing the bubble means "go on", not "never mind".
            let action = pendingAction
            endTurn()
            history = []
            if let action = action { perform(action) }
        }
    }

    /// The world reloaded (e.g. the web content process was killed): forget the current turn.
    func reset() {
        endTurn()
        history = []
    }

    private func startTurn(question: String) {
        endTurn() // a new question replaces any answer still streaming
        let id = turnID
        bridge.send(.setVoiceState(.thinking))
        log("ask: \(question.count) chars, mood \(mood.rawValue)") // the question itself is not logged
        inFlight = brain.answer(
            question: question,
            mood: mood,
            history: history,
            onText: { [weak self] text in
                guard let self = self, id == self.turnID else { return }
                self.show(text)
            },
            completion: { [weak self] result in
                guard let self = self, id == self.turnID else { return }
                self.inFlight = nil
                switch result {
                case .success(let text):
                    self.show(text)
                    self.remember(Exchange(question: question, answer: text))
                case .failure(let error):
                    self.log("brain failed: \(error)")
                    self.show(TurnController.dozedOffText)
                }
                // The answer stays in the bubble (Speaking) until the user closes it or asks again.
            })
    }

    private func startCommand(_ command: CommandMatch) {
        endTurn()
        show(CommandMatcher.reply(command))
        guard case .action(let action) = command else {
            log("command: unknown place")   // the bubble lists the places; the turn stays open for another try
            return
        }
        log("command: \(action)")
        pendingAction = action
        let id = turnID
        schedule(TurnController.commandDelay) { [weak self] in
            guard let self = self, id == self.turnID, let action = self.pendingAction else { return }
            self.endTurn()
            self.perform(action)
        }
    }

    /// Closes the bubble (Idle, which walks Byte to its mood spot), then acts. Order matters: goTo after
    /// idle replaces that walk; a mood or celebration after idle is applied at once instead of deferred.
    private func perform(_ action: WorldAction) {
        history = [] // idle closes the bubble: the conversation is over
        bridge.send(.setVoiceState(.idle))
        switch action {
        case .goTo(let place): bridge.send(.goTo(place))
        case .jump: bridge.send(.jump)
        case .celebrate: bridge.send(.celebrate)
        case .sleep: setMood(.sleepy)
        case .wakeUp: setMood(.happy)
        case .mood(let m): setMood(m)
        }
    }

    /// Changes the mood the world shows and the brain hears. The same mood again does nothing, so repeated
    /// commit events don't keep walking Byte back to its spot.
    func setMood(_ m: Mood) {
        guard m != mood else { return }
        mood = m
        bridge.send(.setMood(m))
    }

    /// Only finished answers are kept: a failed or cut-off answer would mislead the next one.
    private func remember(_ exchange: Exchange) {
        history.append(exchange)
        if history.count > TurnController.historyLimit { history.removeFirst(history.count - TurnController.historyLimit) }
    }

    private func show(_ text: String) {
        if !speaking {
            speaking = true
            bridge.send(.setVoiceState(.speaking))
        }
        bridge.send(.say(text))
    }

    private func endTurn() {
        turnID += 1
        inFlight?.cancel()
        inFlight = nil
        speaking = false
        pendingAction = nil
    }
}

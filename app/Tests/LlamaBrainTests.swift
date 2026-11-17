import Foundation

// Tests for LlamaBrain.swift: prompt, request, stream parser, cleanup, and the real HTTP client
// against Tests/fake_llama_server.py (started by test.sh on FAKE_LLAMA_PORT).

func runLlamaBrainTests() {
    // MARK: Persona
    eq(Persona.systemPrompt(mood: .sleepy),
       "You are Byte, a small robot who lives on a developer's desk. Answer in at most two short sentences that sound natural spoken aloud. No markdown, no code blocks; say commands plainly. Mood: sleepy.",
       "system prompt: spec wording, mood last")
    check(Persona.systemPrompt(mood: .night).hasSuffix("Mood: night owl."), "night mood is spoken as 'night owl'")
    let prefixes = Set(Mood.allCases.map { Persona.systemPrompt(mood: $0).components(separatedBy: "Mood:")[0] })
    eq(prefixes.count, 1, "everything before the mood is identical for every mood (cache-friendly)")

    // MARK: Token
    let tokenDir = NSTemporaryDirectory() + "byte-token-\(getpid())"
    try? FileManager.default.createDirectory(atPath: tokenDir, withIntermediateDirectories: true)
    let tokenFile = tokenDir + "/brain.token"
    let goodToken = String(repeating: "ab", count: 32)
    func writeToken(_ s: String) { try? s.write(toFile: tokenFile, atomically: true, encoding: .utf8) }
    writeToken(goodToken + "\n"); eq(Token.read(from: tokenFile), goodToken, "token read, newline trimmed")
    writeToken(goodToken); eq(Token.read(from: tokenFile), goodToken, "token without newline")
    writeToken("abc"); eq(Token.read(from: tokenFile), nil, "short token rejected")
    writeToken(String(repeating: "AB", count: 32)); eq(Token.read(from: tokenFile), nil, "uppercase rejected")
    writeToken(String(repeating: "zz", count: 32)); eq(Token.read(from: tokenFile), nil, "non-hex rejected")
    writeToken(""); eq(Token.read(from: tokenFile), nil, "empty file rejected")
    try? FileManager.default.removeItem(atPath: tokenFile)
    eq(Token.read(from: tokenFile), nil, "missing file -> nil")
    try? FileManager.default.removeItem(atPath: tokenDir)
    eq(Token.brainPath, "/var/jb/var/mobile/byte/brain.token", "app reads the launcher's brain token path")
    eq(Token.eventsPath, "/var/jb/var/mobile/byte/events.token", "app reads the launcher's events token path")

    // MARK: Request
    let req = BrainRequest.make(question: "how do I undo a commit", mood: .focused, token: goodToken)
    eq(req.value(forHTTPHeaderField: "Authorization"), "Bearer " + goodToken, "token sent as Bearer")
    eq(req.url?.absoluteString, "http://127.0.0.1:8080/v1/chat/completions", "default endpoint is localhost:8080")
    eq(req.httpMethod, "POST", "POST")
    eq(req.value(forHTTPHeaderField: "Content-Type"), "application/json", "JSON body")
    eq(req.timeoutInterval, BrainRequest.timeout, "timeout covers a cold load")
    let body = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
    eq(body["max_tokens"] as? Int, 80, "answers capped at 80 tokens")
    eq(body["stream"] as? Bool, true, "streamed")
    let msgs = body["messages"] as? [[String: String]] ?? []
    eq(msgs.map { $0["role"] ?? "" }, ["system", "user"], "system then user message")
    eq(msgs.last?["content"], "how do I undo a commit", "question passed verbatim")
    check(msgs.first?["content"]?.hasSuffix("Mood: focused.") == true, "mood injected at the end of the system prompt")

    // MARK: Stream parser
    do {
        var p = ChatStreamParser()
        let d = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n"
        eq(p.feed(Data(d.utf8)), [.text("Hi")], "single event")
        eq(p.feed(Data("data: {\"choices\":[{\"del".utf8)), [], "partial line held back")
        eq(p.feed(Data("ta\":{\"content\":\" you\"}}]}\r\n".utf8)), [.text(" you")], "line completed in next chunk, CRLF ok")
        eq(p.feed(Data("data: [DONE]\n".utf8)), [.done], "[DONE]")
        eq(p.feed(Data(": keep-alive comment\nevent: x\n\n".utf8)), [], "comments and other fields ignored")
        eq(p.feed(Data("data: not json\n".utf8)), [], "garbage data ignored")
        eq(p.feed(Data("data: {\"error\":{\"message\":\"oom\"}}\n".utf8)), [.serverError("oom")], "server error event")
        eq(p.feed(Data("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}\n".utf8)), [.done], "finish_reason ends stream")
        eq(p.feed(Data("data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n".utf8)), [], "empty delta ignored")
        let emoji = Data("data: {\"choices\":[{\"delta\":{\"content\":\"🤖\"}}]}\n".utf8)
        var p2 = ChatStreamParser(); var got: [ChatStreamParser.Event] = []
        for b in emoji { got += p2.feed(Data([b])) } // byte by byte, splitting the UTF-8 sequence
        eq(got, [.text("🤖")], "multi-byte character split across chunks")
    }

    // MARK: Cleanup
    eq(AnswerCleanup.clean("Run **`git status`**\n```now```"), "Run git status now", "markdown stripped")
    eq(AnswerCleanup.clean("  two   spaces \n\n "), "two spaces", "whitespace collapsed")
    eq(AnswerCleanup.clean("plain answer."), "plain answer.", "plain text untouched")

    // MARK: Real HTTP against the fake server
    guard let portString = ProcessInfo.processInfo.environment["FAKE_LLAMA_PORT"], let port = Int(portString) else {
        print("SKIP LlamaBrain HTTP tests (FAKE_LLAMA_PORT not set)")
        return
    }
    let endpoint = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!

    let testToken = String(repeating: "ab", count: 32) // what fake_llama_server.py expects
    func ask(_ mode: String, history: [Exchange] = [], brain: LlamaBrain = LlamaBrain(endpoint: endpoint, token: { testToken }),
             cancelAfter: TimeInterval? = nil)
        -> (texts: [String], result: Result<String, Error>?) {
        var texts: [String] = []
        var result: Result<String, Error>?
        let handle = brain.answer(question: mode, mood: .happy, history: history, onText: { texts.append($0) }, completion: { result = $0 })
        let start = Date()
        while result == nil && Date().timeIntervalSince(start) < 10 {
            if let c = cancelAfter, Date().timeIntervalSince(start) > c { handle.cancel(); break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        if cancelAfter != nil { RunLoop.main.run(until: Date().addingTimeInterval(1)) } // let late events arrive
        return (texts, result)
    }
    func success(_ r: Result<String, Error>?) -> String? { if case .success(let s)? = r { return s }; return nil }
    func failure(_ r: Result<String, Error>?) -> BrainError? { if case .failure(let e)? = r { return e as? BrainError }; return nil }

    do {
        let r = ask("normal")
        eq(r.texts, ["Try", "Try git", "Try git rebase."], "streams text so far")
        eq(success(r.result), "Try git rebase.", "completes with full answer")
    }
    do {
        let r = ask("echo")
        let sent = (try? JSONSerialization.jsonObject(with: Data((success(r.result) ?? "{}").utf8))) as? [String: Any]
        eq(sent?["max_tokens"] as? Int, 80, "server received max_tokens 80")
        eq((sent?["messages"] as? [[String: String]])?.count, 2, "no history: system + question")
    }
    do { // history reaches the server as earlier user/assistant turns, oldest first
        let past = [Exchange(question: "what is git stash", answer: "It shelves your changes."),
                    Exchange(question: "how do I get them back", answer: "Run git stash pop.")]
        let r = ask("echo", history: past)
        let sent = (try? JSONSerialization.jsonObject(with: Data((success(r.result) ?? "{}").utf8))) as? [String: Any]
        let messages = (sent?["messages"] as? [[String: String]]) ?? []
        eq(messages.map { $0["role"] ?? "" }, ["system", "user", "assistant", "user", "assistant", "user"], "server got the history in order")
        eq(messages.map { $0["content"] ?? "" }.dropFirst().map { $0 },
           ["what is git stash", "It shelves your changes.", "how do I get them back", "Run git stash pop.", "echo"], "history contents")
    }
    eq(success(ask("split").result), "Hello there.", "events split across TCP chunks")
    eq(success(ask("markdown").result), "Run git status now", "markdown cleaned end to end")
    eq(success(ask("no-done").result), "Cut short", "stream ending without [DONE] keeps what arrived")
    eq(success(ask("slow").result), "Awake.", "slow first token (cold load) still answers")
    eq(failure(ask("empty").result), .emptyAnswer, "empty answer is a failure")
    eq(failure(ask("error-event").result), .server("model failed to load"), "server error event is a failure")
    eq(failure(ask("http500").result), .http(500), "HTTP 500 is a failure")
    do {
        let r = ask("trickle", cancelAfter: 0.5)
        check(r.result == nil, "cancelled answer never completes")
        let n = r.texts.count
        check(n > 0 && n < 30, "cancel stops the stream part way (\(n) updates)")
    }
    do {
        let dead = LlamaBrain(endpoint: URL(string: "http://127.0.0.1:9/v1/chat/completions")!, token: { testToken }) // nothing listens on 9
        if case .unreachable? = failure(ask("normal", brain: dead).result) { check(true, "daemon down -> unreachable") }
        else { check(false, "daemon down -> unreachable") }
    }
    do { // one brain, two answers in a row (task bookkeeping)
        let brain = LlamaBrain(endpoint: endpoint, token: { testToken })
        eq(success(ask("normal", brain: brain).result), "Try git rebase.", "first answer on shared brain")
        eq(success(ask("split", brain: brain).result), "Hello there.", "second answer on shared brain")
    }
    // MARK: Token over HTTP
    do {
        let wrong = LlamaBrain(endpoint: endpoint, token: { String(repeating: "cd", count: 32) })
        eq(failure(ask("normal", brain: wrong).result), .http(401), "wrong token -> 401, no answer")
        var reached = false
        let none = LlamaBrain(endpoint: endpoint, token: { reached = true; return nil })
        let r = ask("normal", brain: none)
        eq(failure(r.result), .noToken, "missing token -> noToken")
        check(reached && r.texts.isEmpty, "nothing streamed without a token")
        var calls = 0
        let h = none.answer(question: "q", mood: .happy, history: [], onText: { _ in calls += 1 }, completion: { _ in calls += 1 })
        h.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        eq(calls, 0, "cancelled no-token answer makes no callbacks")
    }
}

import Foundation

// The real brain: llama-server on 127.0.0.1:8080 (brain/), streamed through its chat endpoint.
// Foundation only, so the request building and stream parsing are unit-tested on the Mac.

enum Persona {
    /// The spec's system prompt (docs/TECHNICAL.md, "Brain"), with the current mood injected.
    /// The mood goes last (decision 2026-11-16, 2A): everything before it is identical between
    /// questions, so llama-server's prompt cache can skip re-reading it even when the mood changes.
    static func systemPrompt(mood: Mood) -> String {
        "You are Byte, a small robot who lives on a developer's desk. " +
        "Answer in at most two short sentences that sound natural spoken aloud. " +
        "No markdown, no code blocks; say commands plainly. " +
        "Mood: \(spokenName(mood))."
    }

    static func spokenName(_ mood: Mood) -> String {
        mood == .night ? "night owl" : mood.rawValue
    }
}

/// Builds the llama-server request. Uses the OpenAI-style chat endpoint so the server applies
/// the model's own chat template, read from the GGUF (the raw /completion endpoint would need it hand-formatted).
enum BrainRequest {
    static let endpoint = URL(string: "http://127.0.0.1:8080/v1/chat/completions")!
    static let maxTokens = 80          // spec: answers capped at 80 tokens
    /// Covers a cold model load (spec budget 15 s) plus 80 tokens at a few tokens per second.
    static let timeout: TimeInterval = 90

    /// Messages in order: system, then each earlier exchange (user, assistant), then the new question.
    static func messages(question: String, mood: Mood, history: [Exchange]) -> [[String: String]] {
        var m = [["role": "system", "content": Persona.systemPrompt(mood: mood)]]
        for e in history {
            m.append(["role": "user", "content": e.question])
            m.append(["role": "assistant", "content": e.answer])
        }
        m.append(["role": "user", "content": question])
        return m
    }

    static func make(question: String, mood: Mood, history: [Exchange] = [], token: String, endpoint: URL = endpoint) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "messages": messages(question: question, mood: mood, history: history),
            "stream": true,
            "max_tokens": maxTokens,
            "temperature": 0.7,
            "cache_prompt": true // the shared prefix (system prompt, earlier exchanges) is reused between questions
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// Incremental parser for the server-sent-events stream. Feed it bytes as they arrive;
/// it returns each piece of answer text and reports when the stream says it's done.
struct ChatStreamParser {
    enum Event: Equatable {
        case text(String)
        case done
        case serverError(String)
    }

    private var buffer = Data()

    mutating func feed(_ data: Data) -> [Event] {
        buffer.append(data)
        var events: [Event] = []
        // Events are separated by newlines; a chunk may end mid-line, so keep the tail.
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard var line = String(data: lineData, encoding: .utf8) else { continue }
            if line.hasSuffix("\r") { line.removeLast() }
            if let event = ChatStreamParser.parse(line: line) { events.append(event) }
        }
        return events
    }

    static func parse(line: String) -> Event? {
        guard line.hasPrefix("data:") else { return nil } // comments, "event:" lines, blanks
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any] {
            return .serverError((error["message"] as? String) ?? "unknown server error")
        }
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return nil }
        if let content = (choice["delta"] as? [String: Any])?["content"] as? String, !content.isEmpty {
            return .text(content)
        }
        if let reason = choice["finish_reason"] as? String, !reason.isEmpty { return .done }
        return nil
    }
}

/// Removes things that shouldn't be in a one-line spoken bubble even if the model ignores the prompt.
enum AnswerCleanup {
    static func clean(_ text: String) -> String {
        var s = text
        for token in ["```", "**", "__", "`"] { s = s.replacingOccurrences(of: token, with: "") }
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BrainError: Error, Equatable {
    case unreachable(String)        // daemon not running / connection refused
    case http(Int)
    case server(String)
    case emptyAnswer
    case noToken                    // brain.token missing or malformed; nothing is sent
}

/// Streams one answer from llama-server. Callbacks are delivered on the main queue (Brain contract).
final class LlamaBrain: NSObject, Brain, URLSessionDataDelegate {
    private let endpoint: URL
    private let token: () -> String?
    init(endpoint: URL = BrainRequest.endpoint, token: @escaping () -> String? = { Token.read(from: Token.brainPath) }) {
        self.endpoint = endpoint
        self.token = token
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral   // nothing cached to disk
        config.timeoutIntervalForRequest = BrainRequest.timeout
        config.timeoutIntervalForResource = BrainRequest.timeout
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private final class Stream: Cancellable {
        var parser = ChatStreamParser()
        var text = ""
        var finished = false
        var status = 200
        let onText: (String) -> Void
        let completion: (Result<String, Error>) -> Void
        weak var task: URLSessionDataTask?
        init(onText: @escaping (String) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
            self.onText = onText; self.completion = completion
        }
        func cancel() { finished = true; task?.cancel() }
        func finish(_ result: Result<String, Error>) {
            guard !finished else { return }
            finished = true
            completion(result)
        }
    }
    private var streams: [Int: Stream] = [:]

    func answer(question: String, mood: Mood, history: [Exchange],
                onText: @escaping (String) -> Void,
                completion: @escaping (Result<String, Error>) -> Void) -> Cancellable {
        let stream = Stream(onText: onText, completion: completion)
        guard let token = token() else {
            DispatchQueue.main.async { stream.finish(.failure(BrainError.noToken)) } // async, like every other result
            return stream
        }
        let task = session.dataTask(with: BrainRequest.make(question: question, mood: mood, history: history, token: token, endpoint: endpoint))
        stream.task = task
        streams[task.taskIdentifier] = stream
        task.resume()
        return stream
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        streams[dataTask.taskIdentifier]?.status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let s = streams[dataTask.taskIdentifier], !s.finished else { return }
        guard s.status == 200 else { return } // body of an error response; reported on completion
        for event in s.parser.feed(data) {
            switch event {
            case .text(let piece):
                s.text += piece
                s.onText(AnswerCleanup.clean(s.text))
            case .done:
                let final = AnswerCleanup.clean(s.text)
                s.finish(final.isEmpty ? .failure(BrainError.emptyAnswer) : .success(final))
                dataTask.cancel()
                return
            case .serverError(let message):
                s.finish(.failure(BrainError.server(message)))
                dataTask.cancel()
                return
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let s = streams.removeValue(forKey: task.taskIdentifier) else { return }
        if let error = error as NSError?, error.code == NSURLErrorCancelled { return s.finish(.failure(error)) }
        if let error = error { return s.finish(.failure(BrainError.unreachable(error.localizedDescription))) }
        if s.status != 200 { return s.finish(.failure(BrainError.http(s.status))) }
        let final = AnswerCleanup.clean(s.text) // stream ended without [DONE]: use what arrived
        s.finish(final.isEmpty ? .failure(BrainError.emptyAnswer) : .success(final))
    }
}

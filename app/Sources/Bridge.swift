import Foundation

// The window.byte bridge between this shell and the 3D world (docs/TECHNICAL.md, "Native app to 3D world bridge").
// Foundation only, so it can be unit-tested on the Mac (see Tests/ and test.sh).

/// Moods the world knows (keys of MOODS in byte-world/main.js).
enum Mood: String, CaseIterable {
    case happy, focused, sleepy, bored, night, celebrating
}

/// Voice states the world can show (VOICE_STATES in byte-world/main.js).
enum VoiceState: String, CaseIterable {
    case idle, listening, thinking, speaking
}

/// World -> app: what main.js posts through webkit.messageHandlers.byte.postMessage(...).
enum WorldMessage: Equatable {
    case ready
    case askTapped
    case ask(text: String)   // v1 typed-question test path; goes away when voice lands in v2
    case askClosed

    /// Longest question passed to the brain; the model only has a 1,024-token context.
    static let maxQuestionLength = 500

    /// Returns nil for anything malformed or unknown, so new message types can't crash old shells.
    static func parse(_ body: Any) -> WorldMessage? {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready": return .ready
        case "askTapped": return .askTapped
        case "askClosed": return .askClosed
        case "ask":
            guard let raw = dict["text"] as? String else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return .ask(text: String(text.prefix(maxQuestionLength)))
        default:
            return nil
        }
    }
}

/// App -> world: one call on window.byte, rendered as JavaScript for WKWebView.evaluateJavaScript.
enum WorldCommand: Equatable {
    case setMood(Mood)
    case setVoiceState(VoiceState)
    case say(String)
    case setLevel(Double)
    case celebrate
    case goTo(Place)   // typed commands (Commands.swift)
    case jump

    var javaScript: String {
        switch self {
        case .setMood(let mood): return "window.byte.setMood(\(jsStringLiteral(mood.rawValue)))"
        case .setVoiceState(let state): return "window.byte.setVoiceState(\(jsStringLiteral(state.rawValue)))"
        case .say(let text): return "window.byte.say(\(jsStringLiteral(text)))"
        case .setLevel(let level):
            let clamped = level.isFinite ? min(1, max(0, level)) : 0
            return "window.byte.setLevel(\(clamped))"
        case .celebrate: return "window.byte.celebrate()"
        case .goTo(let place): return "window.byte.goTo(\(jsStringLiteral(place.rawValue)))"
        case .jump: return "window.byte.jump()"
        }
    }
}

/// A JavaScript string literal for any Swift string: JSON-encoded, plus the two line separators
/// and "</" escaped so the result is safe anywhere a script can appear.
func jsStringLiteral(_ s: String) -> String {
    // Wrapping in an array keeps JSONSerialization happy on every iOS version (no fragments option needed).
    guard let data = try? JSONSerialization.data(withJSONObject: [s]),
          let json = String(data: data, encoding: .utf8) else { return "\"\"" }
    let literal = String(json.dropFirst().dropLast()) // strip [ ]
    return literal
        .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        .replacingOccurrences(of: "</", with: "<\\/")
}

/// Sends commands to the world, holding them until the world has posted `ready`.
/// If the web content process dies, call `markNotReady()` and commands queue again until the reload is ready.
final class WorldBridge {
    /// Bound on queued commands; a world that never loads must not grow memory forever.
    static let maxPending = 100

    private let evaluate: (String) -> Void
    private(set) var isReady = false
    private(set) var pending: [WorldCommand] = []

    init(evaluate: @escaping (String) -> Void) {
        self.evaluate = evaluate
    }

    func send(_ command: WorldCommand) {
        guard isReady else {
            if pending.count >= WorldBridge.maxPending { pending.removeFirst() }
            pending.append(command)
            return
        }
        evaluate(command.javaScript)
    }

    func markReady() {
        isReady = true
        let queued = pending
        pending = []
        queued.forEach { evaluate($0.javaScript) }
    }

    func markNotReady() {
        isReady = false
    }
}

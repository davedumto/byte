import Foundation

/// Shared secrets made by brain/launcher on the iPod (64 lowercase hex characters, mode 600, owner mobile).
///  - brain: the app -> llama-server key, so web pages open in Safari on the device can't use the brain
///    (decision 2026-11-16, 1A).
///  - events: the Mac -> app key for push events on port 7420, kept separate so a leaked Mac token can
///    only make Byte dance (step 5, decision 2A).
enum Token {
    static let brainPath = "/var/jb/var/mobile/byte/brain.token"
    static let eventsPath = "/var/jb/var/mobile/byte/events.token"

    /// The token, or nil if the file is missing or isn't 64 lowercase hex characters.
    /// Read for every request, so a regenerated token is picked up without restarting the app.
    static func read(from path: String) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = Set("0123456789abcdef")
        guard token.count == 64, token.allSatisfy({ hex.contains($0) }) else { return nil }
        return token
    }
}

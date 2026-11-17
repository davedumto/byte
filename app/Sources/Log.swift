import Foundation

/// Logs to the system log and to /var/jb/var/mobile/byte/byte.log (docs/TECHNICAL.md, "Daily loop").
/// Never log questions, answers or audio: counts and states only.
enum Log {
    static let directory = "/var/jb/var/mobile/byte"
    static let path = directory + "/byte.log"
    /// When the log passes this size it is moved to byte.log.1 (one old copy kept).
    static let maxBytes: UInt64 = 1_000_000

    private static let queue = DispatchQueue(label: "byte.log")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func info(_ message: String) {
        NSLog("[Byte] %@", message)
        let line = stamp.string(from: Date()) + " " + message + "\n"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? UInt64, size > maxBytes {
                try? fm.removeItem(atPath: path + ".1")
                try? fm.moveItem(atPath: path, toPath: path + ".1")
            }
            if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } catch {
            NSLog("[Byte] log file unavailable: %@", String(describing: error)) // keep running on the system log
        }
    }
}

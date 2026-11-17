import Foundation

// Work events from the Mac on port 7420 (docs/TECHNICAL.md, "Interfaces", "Event schema"; step 5, decisions 1A/2A/3A).
// Foundation only: HTTP parsing, routing and the event schema are unit-tested on the Mac.
// EventServer.swift does the networking.

// MARK: - Events

/// What the Mac reports. v1 acts on push only; the others are accepted now so the v2 mood engine can use them.
enum WorkEvent: Equatable {
    case push(commits: Int)
    case commit
    case testPass
    case testFail
    case breakTaken
}

enum ParsedEvent: Equatable {
    case event(WorkEvent)
    case unknownType     // spec: unknown types are ignored, so new events can be added later
    case invalid
}

enum EventSchema {
    static let maxCommits = 100_000
    static let maxNameLength = 200   // repo and branch: checked, never logged or shown

    private struct Payload: Decodable {
        let type: String
        let repo: String?
        let branch: String?
        let commits: Int?   // JSONDecoder rejects true/false, 1.5 and "3" here
        let ts: String?
    }

    /// What the app log says about an event (type and count only, never repo or branch names).
    static func logText(_ parsed: ParsedEvent) -> String {
        switch parsed {
        case .event(.push(let commits)): return "push, \(commits) commit\(commits == 1 ? "" : "s")"
        case .event(.commit): return "commit"
        case .event(.testPass): return "test_pass (no effect until the v2 mood engine)"
        case .event(.testFail): return "test_fail (no effect until the v2 mood engine)"
        case .event(.breakTaken): return "break (no effect until the v2 mood engine)"
        case .unknownType: return "unknown type, ignored"
        case .invalid: return "invalid"
        }
    }

    static func parse(_ body: Data) -> ParsedEvent {
        guard let p = try? JSONDecoder().decode(Payload.self, from: body) else { return .invalid }
        for name in [p.repo, p.branch, p.ts] {
            if let name = name, name.count > maxNameLength { return .invalid }
        }
        switch p.type {
        case "push":
            let commits = p.commits ?? 0
            guard (0...maxCommits).contains(commits) else { return .invalid }
            return .event(.push(commits: commits))
        case "commit": return .event(.commit)
        case "test_pass": return .event(.testPass)
        case "test_fail": return .event(.testFail)
        case "break": return .event(.breakTaken)
        default: return p.type.isEmpty ? .invalid : .unknownType
        }
    }
}

/// What an event makes Byte do.
enum Reaction: Equatable {
    case celebrate
    case mood(Mood)
}

/// Turns events into reactions. A push celebrates, at most once per `minCelebrationGap` (a flood of pushes
/// or a stuck script gives one party; the world's own celebration lasts 10 s). A commit means you're working,
/// so Byte turns Focused (decision 2026-11-17, 2A), except right after a push, so the commit hook never cuts
/// a celebration short. test_pass, test_fail and break do nothing until the v2 mood engine.
final class EventReactor {
    static let minCelebrationGap: TimeInterval = 10
    private var lastCelebration: Date?

    func react(to event: WorkEvent, now: Date = Date()) -> Reaction? {
        switch event {
        case .push:
            if let last = lastCelebration, celebratedRecently(last, now) { return nil }
            lastCelebration = now
            return .celebrate
        case .commit:
            if let last = lastCelebration, celebratedRecently(last, now) { return nil }
            return .mood(.focused)
        case .testPass, .testFail, .breakTaken:
            return nil
        }
    }

    /// A clock that jumps backwards never blocks reactions forever.
    private func celebratedRecently(_ last: Date, _ now: Date) -> Bool {
        now >= last && now.timeIntervalSince(last) < EventReactor.minCelebrationGap
    }
}

// MARK: - HTTP

struct HTTPRequest: Equatable {
    let method: String
    let path: String                  // without any query string
    let headers: [String: String]     // names lowercased
    let body: Data
}

struct HTTPResponse: Equatable {
    let status: Int
    let json: String
    var extraHeaders: [(String, String)] = []

    static func == (a: HTTPResponse, b: HTTPResponse) -> Bool {
        a.status == b.status && a.json == b.json && a.extraHeaders.map { "\($0.0):\($0.1)" } == b.extraHeaders.map { "\($0.0):\($0.1)" }
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, json: "{\"ok\":false,\"error\":\(jsonString(message))}")
    }

    static let reasons: [Int: String] = [
        200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
        405: "Method Not Allowed", 408: "Request Timeout", 411: "Length Required", 413: "Payload Too Large",
        431: "Request Header Fields Too Large", 501: "Not Implemented", 503: "Service Unavailable"
    ]

    /// The bytes on the wire. Every response closes the connection (one request per connection).
    var data: Data {
        let body = Data(json.utf8)
        var head = "HTTP/1.1 \(status) \(HTTPResponse.reasons[status] ?? "Error")\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if status == 401 { head += "WWW-Authenticate: Bearer\r\n" }
        for (name, value) in extraHeaders { head += "\(name): \(value)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}

private func jsonString(_ s: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [s]), let json = String(data: data, encoding: .utf8) else { return "\"\"" }
    return String(json.dropFirst().dropLast())
}

enum HTTPParseResult: Equatable {
    case incomplete               // keep reading
    case complete(HTTPRequest)
    case invalid(HTTPResponse)    // send this and close
}

/// A deliberately small HTTP/1.x request parser: one request per connection, Content-Length bodies only.
enum HTTPParser {
    static let maxHeaderBytes = 8 * 1024
    static let maxBodyBytes = 4 * 1024
    /// Most the server ever needs to buffer for one request.
    static var maxRequestBytes: Int { maxHeaderBytes + 4 + maxBodyBytes }

    private static let headerEnd = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> HTTPParseResult {
        guard let end = buffer.range(of: headerEnd) else {
            return buffer.count > maxHeaderBytes ? .invalid(.error(431, "headers too large")) : .incomplete
        }
        guard end.lowerBound <= maxHeaderBytes else { return .invalid(.error(431, "headers too large")) }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .invalid(.error(400, "headers are not UTF-8"))
        }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(requestLine[2]),
              !requestLine[0].isEmpty, requestLine[1].hasPrefix("/") else {
            return .invalid(.error(400, "bad request line"))
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return .invalid(.error(400, "bad header")) }
            let name = line[..<colon].lowercased()
            guard !name.contains(" ") && !name.contains("\t") else { return .invalid(.error(400, "bad header")) }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length", let existing = headers[name], existing != value {
                return .invalid(.error(400, "conflicting Content-Length")) // request smuggling guard
            }
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil { return .invalid(.error(501, "chunked bodies are not supported")) }

        var length = 0
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.count <= 9, raw.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(raw) else {
                return .invalid(.error(400, "bad Content-Length"))
            }
            length = n
        } else if requestLine[0] == "POST" {
            return .invalid(.error(411, "Content-Length required"))
        }
        guard length <= maxBodyBytes else { return .invalid(.error(413, "body too large")) }

        let bodyStart = end.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + length)]
        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return .complete(HTTPRequest(method: String(requestLine[0]), path: path, headers: headers, body: Data(body)))
    }
}

/// Answers one request. `expectedToken` is the events token (nil if the file is missing or malformed).
/// The token is checked before anything else, so without it every path looks the same.
enum EventRouter {
    static func respond(to request: HTTPRequest, expectedToken: String?) -> (HTTPResponse, ParsedEvent?) {
        guard let expected = expectedToken else { return (.error(503, "events token missing on the iPod"), nil) }
        guard let auth = request.headers["authorization"], bearerMatches(auth, expected) else {
            return (.error(401, "missing or wrong token"), nil)
        }
        switch (request.method, request.path) {
        case ("GET", "/health"), ("HEAD", "/health"):
            return (HTTPResponse(status: 200, json: "{\"ok\":true,\"name\":\"Byte\"}"), nil)
        case ("POST", "/event"):
            let parsed = EventSchema.parse(request.body)
            switch parsed {
            case .invalid: return (.error(400, "not a valid event"), nil)
            case .unknownType: return (HTTPResponse(status: 202, json: "{\"ok\":true,\"ignored\":true}"), parsed)
            case .event: return (HTTPResponse(status: 202, json: "{\"ok\":true}"), parsed)
            }
        case (_, "/health"):
            var r = HTTPResponse.error(405, "use GET"); r.extraHeaders = [("Allow", "GET, HEAD")]; return (r, nil)
        case (_, "/event"):
            var r = HTTPResponse.error(405, "use POST"); r.extraHeaders = [("Allow", "POST")]; return (r, nil)
        default:
            return (.error(404, "no such endpoint"), nil)
        }
    }

    /// "Bearer <token>" (scheme case-insensitive), compared in constant time.
    static func bearerMatches(_ header: String, _ expected: String) -> Bool {
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        let given = Array(parts[1].trimmingCharacters(in: .whitespaces).utf8), want = Array(expected.utf8)
        guard given.count == want.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<want.count { diff |= given[i] ^ want[i] }
        return diff == 0
    }
}

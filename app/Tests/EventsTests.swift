import Foundation
import Network

// Tests for Events.swift (schema, HTTP parser, router, reactor) and EventServer.swift (a real listener on a
// local port, spoken to over raw sockets so malformed requests can be sent too).

func runEventsTests() {
    let token = String(repeating: "ef", count: 32)
    func body(_ s: String) -> Data { Data(s.utf8) }

    // MARK: Event schema
    eq(EventSchema.parse(body(#"{"type":"push","repo":"vellar-sdk","branch":"main","commits":3,"ts":"2026-11-16T15:40:00Z"}"#)),
       .event(.push(commits: 3)), "spec example push")
    eq(EventSchema.parse(body(#"{"type":"push"}"#)), .event(.push(commits: 0)), "push without commits")
    eq(EventSchema.parse(body(#"{"type":"push","commits":0}"#)), .event(.push(commits: 0)), "push with 0 commits")
    eq(EventSchema.parse(body(#"{"type":"push","extra":{"x":1}}"#)), .event(.push(commits: 0)), "unknown keys ignored")
    eq(EventSchema.parse(body(#"{"type":"commit"}"#)), .event(.commit), "commit")
    eq(EventSchema.parse(body(#"{"type":"test_pass"}"#)), .event(.testPass), "test_pass")
    eq(EventSchema.parse(body(#"{"type":"test_fail"}"#)), .event(.testFail), "test_fail")
    eq(EventSchema.parse(body(#"{"type":"break"}"#)), .event(.breakTaken), "break")
    eq(EventSchema.parse(body(#"{"type":"deploy"}"#)), .unknownType, "unknown type is ignored, not an error")
    for bad in [#"{"type":"push","commits":-1}"#, #"{"type":"push","commits":100001}"#, #"{"type":"push","commits":1.5}"#,
                #"{"type":"push","commits":"3"}"#, #"{"type":"push","commits":true}"#, #"{"type":""}"#, #"{"type":7}"#,
                #"{"repo":"x"}"#, #"[]"#, #""push""#, "", "not json", #"{"type":"push","repo":5}"#,
                "{\"type\":\"push\",\"repo\":\"\(String(repeating: "r", count: 201))\"}"] {
        eq(EventSchema.parse(body(bad)), .invalid, "invalid event: \(bad.prefix(40))")
    }
    eq(EventSchema.parse(body("{\"type\":\"push\",\"repo\":\"\(String(repeating: "r", count: 200))\"}")), .event(.push(commits: 0)),
       "200-char repo name is fine")
    eq(EventSchema.logText(.event(.push(commits: 1))), "push, 1 commit", "log text singular")
    eq(EventSchema.logText(.event(.push(commits: 3))), "push, 3 commits", "log text plural")
    check(!EventSchema.logText(.event(.push(commits: 3))).contains("vellar"), "log text never has the repo")

    // MARK: Reactor: push celebrates, at most once per gap; other events do nothing yet
    do {
        let r = EventReactor(), t0 = Date(timeIntervalSince1970: 1_000_000)
        eq(r.react(to: .push(commits: 1), now: t0), .celebrate, "push celebrates")
        eq(r.react(to: .push(commits: 1), now: t0.addingTimeInterval(3)), nil, "second push within the gap is dropped")
        eq(r.react(to: .push(commits: 1), now: t0.addingTimeInterval(EventReactor.minCelebrationGap)), .celebrate, "push after the gap celebrates")
        eq(r.react(to: .push(commits: 1), now: t0), .celebrate, "clock going backwards never blocks forever")
        for e in [WorkEvent.commit, .testPass, .testFail, .breakTaken] {
            eq(EventReactor().react(to: e), nil, "\(e) has no effect in v1")
        }
    }

    // MARK: HTTP parser
    func req(_ s: String) -> HTTPParseResult { HTTPParser.parse(Data(s.utf8)) }
    func status(_ r: HTTPParseResult) -> Int? { if case .invalid(let resp) = r { return resp.status }; return nil }
    let postHead = "POST /event HTTP/1.1\r\nHost: byte\r\nContent-Type: application/json\r\n"
    let pushJSON = #"{"type":"push","commits":2}"#
    if case .complete(let r) = req(postHead + "Authorization: Bearer x\r\nContent-Length: \(pushJSON.utf8.count)\r\n\r\n" + pushJSON) {
        eq(r.method, "POST", "method"); eq(r.path, "/event", "path"); eq(r.body, body(pushJSON), "body")
        eq(r.headers["authorization"], "Bearer x", "header names lowercased, value trimmed")
    } else { check(false, "complete POST parses") }
    if case .complete(let r) = req("GET /health?probe=1 HTTP/1.0\r\n\r\n") { eq(r.path, "/health", "query string dropped") }
    else { check(false, "GET with query parses") }
    eq(req(""), .incomplete, "empty buffer is incomplete")
    eq(req("POST /event HTTP/1.1\r\nContent-Length: 10\r\n"), .incomplete, "headers not finished")
    eq(req(postHead + "Content-Length: 10\r\n\r\n{\"ty"), .incomplete, "body not finished")
    if case .complete(let r) = req(postHead + "Content-Length: 2\r\n\r\n{}EXTRA") { eq(r.body, body("{}"), "bytes past Content-Length ignored") }
    else { check(false, "extra bytes after the body") }
    eq(status(req(postHead + "\r\n")), 411, "POST without Content-Length")
    eq(status(req(postHead + "Content-Length: 4097\r\n\r\n")), 413, "body over 4 KB")
    eq(status(req(postHead + "Content-Length: -1\r\n\r\n")), 400, "negative Content-Length")
    eq(status(req(postHead + "Content-Length: 1e3\r\n\r\n")), 400, "non-digit Content-Length")
    eq(status(req(postHead + "Content-Length: 99999999999999999999\r\n\r\n")), 400, "huge Content-Length")
    eq(status(req(postHead + "Content-Length: 2\r\nContent-Length: 5\r\n\r\n{}")), 400, "conflicting Content-Length")
    eq(status(req(postHead + "Transfer-Encoding: chunked\r\n\r\n")), 501, "chunked refused")
    eq(status(req("GARBAGE\r\n\r\n")), 400, "bad request line")
    eq(status(req("GET /health HTTP/2\r\n\r\n")), 400, "unknown HTTP version")
    eq(status(req("GET health HTTP/1.1\r\n\r\n")), 400, "target must start with /")
    eq(status(req("GET /health HTTP/1.1\r\nno colon here\r\n\r\n")), 400, "header without colon")
    eq(status(req("GET /health HTTP/1.1\r\nBad Name: x\r\n\r\n")), 400, "header name with a space")
    eq(status(HTTPParser.parse(Data("GET / HTTP/1.1\r\nX: ".utf8) + Data(repeating: 65, count: HTTPParser.maxHeaderBytes))), 431,
       "endless headers stop at 8 KB")
    eq(status(HTTPParser.parse(Data("GET / HTTP/1.1\r\n".utf8) + Data([0xff, 0xfe]) + Data("\r\n\r\n".utf8))), 400, "non-UTF-8 headers")

    // MARK: Router
    func request(_ method: String, _ path: String, auth: String? = "Bearer \(token)", json: String = "") -> HTTPRequest {
        HTTPRequest(method: method, path: path, headers: auth.map { ["authorization": $0] } ?? [:], body: body(json))
    }
    func route(_ r: HTTPRequest, expected: String? = token) -> (Int, ParsedEvent?) {
        let (resp, ev) = EventRouter.respond(to: r, expectedToken: expected); return (resp.status, ev)
    }
    eq(route(request("POST", "/event", json: pushJSON)).0, 202, "push accepted")
    eq(route(request("POST", "/event", json: pushJSON)).1, .event(.push(commits: 2)), "push handed to the app")
    eq(route(request("POST", "/event", json: #"{"type":"deploy"}"#)).0, 202, "unknown type accepted (ignored)")
    eq(route(request("POST", "/event", json: "nope")).0, 400, "bad JSON")
    eq(route(request("POST", "/event", json: "nope")).1, nil, "bad JSON reaches nothing")
    eq(route(request("GET", "/health")).0, 200, "health")
    eq(route(request("HEAD", "/health")).0, 200, "health HEAD")
    eq(route(request("POST", "/event", auth: nil, json: pushJSON)).0, 401, "no token")
    eq(route(request("POST", "/event", auth: "Bearer " + String(repeating: "00", count: 32), json: pushJSON)).0, 401, "wrong token")
    eq(route(request("POST", "/event", auth: "Bearer " + token.dropLast(), json: pushJSON)).0, 401, "token one char short")
    eq(route(request("POST", "/event", auth: "Bearer " + token + "0", json: pushJSON)).0, 401, "token one char long")
    eq(route(request("POST", "/event", auth: "Basic " + token, json: pushJSON)).0, 401, "wrong scheme")
    eq(route(request("POST", "/event", auth: token, json: pushJSON)).0, 401, "token without scheme")
    eq(route(request("POST", "/event", auth: "bearer \(token)", json: pushJSON)).0, 202, "scheme is case-insensitive")
    eq(route(request("GET", "/health", auth: nil)).0, 401, "health needs the token too")
    eq(route(request("GET", "/secret", auth: nil)).0, 401, "unknown paths look the same without a token")
    eq(route(request("POST", "/event", json: pushJSON), expected: nil).0, 503, "no events token on the iPod")
    eq(route(request("POST", "/event", json: pushJSON), expected: nil).1, nil, "no token file: nothing happens")
    eq(route(request("GET", "/event")).0, 405, "GET /event")
    eq(route(request("POST", "/health")).0, 405, "POST /health")
    eq(route(request("GET", "/nope")).0, 404, "unknown path")
    let wire = String(data: HTTPResponse.error(401, "x").data, encoding: .utf8) ?? ""
    check(wire.hasPrefix("HTTP/1.1 401 Unauthorized\r\n") && wire.contains("WWW-Authenticate: Bearer\r\n")
          && wire.contains("Connection: close\r\n") && wire.hasSuffix("\r\n\r\n{\"ok\":false,\"error\":\"x\"}"), "response bytes")
    check(String(data: HTTPResponse.error(400, "say \"hi\"").data, encoding: .utf8)?.contains(#""error":"say \"hi\"""#) == true,
          "error message JSON-escaped")

    // MARK: Local-network check
    for (ip, local) in [([10, 0, 0, 5], true), ([192, 168, 0, 12], true), ([172, 16, 1, 1], true), ([172, 31, 255, 1], true),
                        ([169, 254, 3, 4], true), ([127, 0, 0, 1], true), ([172, 32, 0, 1], false), ([8, 8, 8, 8], false),
                        ([192, 169, 0, 1], false), ([100, 64, 0, 1], false)] as [([UInt8], Bool)] {
        eq(EventServer.isLocalIPv4(ip), local, "IPv4 \(ip) local=\(local)")
    }
    func v6(_ s: String) -> [UInt8] { Array(IPv6Address(s)!.rawValue) }
    eq(EventServer.isLocalIPv6(v6("::1")), true, "::1"); eq(EventServer.isLocalIPv6(v6("fe80::1")), true, "fe80::1")
    eq(EventServer.isLocalIPv6(v6("fd12::1")), true, "fd12::1"); eq(EventServer.isLocalIPv6(v6("::ffff:192.168.0.2")), true, "mapped private v4")
    eq(EventServer.isLocalIPv6(v6("::ffff:8.8.8.8")), false, "mapped public v4"); eq(EventServer.isLocalIPv6(v6("2001:db8::1")), false, "global v6")
    eq(EventServer.isLocalIPv6(v6("::")), false, "::"); eq(EventServer.isLocalIPv4([1, 2, 3]), false, "short IPv4")
    eq(EventServer.isLocal(.hostPort(host: "byte.local", port: 1)), false, "a name is not an address")

    // MARK: EventServer on a real local port
    runEventServerTests(token: token)
}

/// Spins the main run loop (events are delivered on the main queue) until `done` or timeout.
private func waitUntil(timeout: TimeInterval = 3, _ done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return done()
}

/// Sends raw bytes to 127.0.0.1:port and returns everything the server sends back before closing.
private func rawExchange(port: UInt16, _ bytes: Data, closeWrite: Bool = false, timeout: Int = 3) -> String {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return "" }
    defer { close(fd) }
    var tv = timeval(tv_sec: timeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    guard ok == 0 else { return "" }
    _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, bytes.count, 0) }
    if closeWrite { shutdown(fd, SHUT_WR) }
    var out = Data(), buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = recv(fd, &buf, buf.count, 0)
        if n <= 0 { break }
        out.append(contentsOf: buf[0..<n])
    }
    return String(data: out, encoding: .utf8) ?? ""
}

private func runEventServerTests(token: String) {
    let port: UInt16 = 17420
    var events: [ParsedEvent] = []
    var tokenValue: String? = token
    var ready = false
    let server = EventServer(port: port, advertise: false, token: { tokenValue }) { events.append($0) }
    server.onReady = { ready = true }
    server.start()
    guard waitUntil({ ready }) else { return check(false, "event server starts on \(port)") }

    func post(_ json: String, auth: String? = nil) -> String {
        var head = "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n"
        head += "Authorization: \(auth ?? "Bearer \(token)")\r\n\r\n"
        return rawExchange(port: port, Data((head + json).utf8))
    }
    check(post(#"{"type":"push","repo":"r","branch":"main","commits":3}"#).hasPrefix("HTTP/1.1 202"), "server accepts a push")
    check(waitUntil({ events == [.event(.push(commits: 3))] }), "push delivered on the main queue")
    check(post(#"{"type":"push"}"#, auth: "Bearer nope").hasPrefix("HTTP/1.1 401"), "server refuses a wrong token")
    check(post("{oops").hasPrefix("HTTP/1.1 400"), "server refuses bad JSON")
    check(rawExchange(port: port, Data("GET /health HTTP/1.1\r\nAuthorization: Bearer \(token)\r\n\r\n".utf8))
            .contains("{\"ok\":true,\"name\":\"Byte\"}"), "health over the wire")

    // a request split across several packets
    do {
        let fd = socket(AF_INET, SOCK_STREAM, 0); defer { close(fd) }
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = port.bigEndian; addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        let json = #"{"type":"push","commits":1}"#
        let parts = ["POST /event HTTP/1.1\r\nAuthorization: Bearer \(token)\r\n", "Content-Length: \(json.utf8.count)\r\n\r\n", json]
        for p in parts { _ = p.withCString { send(fd, $0, strlen($0), 0) }; usleep(50_000) }
        var buf = [UInt8](repeating: 0, count: 512); var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let n = recv(fd, &buf, buf.count, 0)
        check(n > 0 && String(decoding: buf[0..<max(n, 0)], as: UTF8.self).hasPrefix("HTTP/1.1 202"), "request in three packets")
        check(waitUntil({ events.count == 2 }), "split request delivered once")
    }

    // a client that sends half a request and goes quiet gets a 408 and is closed
    let started = Date()
    let slow = rawExchange(port: port, Data("POST /event HTTP/1.1\r\nContent-Length: 50\r\n".utf8), timeout: 8)
    check(slow.hasPrefix("HTTP/1.1 408"), "half a request times out with 408")
    check(Date().timeIntervalSince(started) < EventServer.requestTimeout + 2, "timeout is about \(EventServer.requestTimeout) s")
    // a client that gives up mid-request is just closed
    eq(rawExchange(port: port, Data("POST /event HTTP/1.1\r\n".utf8), closeWrite: true), "", "peer gone mid-request: closed, no reply")
    check(rawExchange(port: port, Data("POST /event HTTP/1.1\r\nContent-Length: 999999\r\n\r\n".utf8)).hasPrefix("HTTP/1.1 413"), "oversized body refused early")

    // token file missing on the iPod
    tokenValue = nil
    check(post(#"{"type":"push"}"#).hasPrefix("HTTP/1.1 503"), "no token file -> 503")
    tokenValue = token
    eq(events.count, 2, "refused requests never reach the app")

    // stop closes the port; start again reopens it
    server.stop()
    check(waitUntil({ rawExchange(port: port, Data("GET /health HTTP/1.1\r\n\r\n".utf8), timeout: 1).isEmpty }), "stopped server answers nothing")
    ready = false
    server.start()
    check(waitUntil({ ready }), "server restarts after stop")
    check(post(#"{"type":"push","commits":4}"#).hasPrefix("HTTP/1.1 202"), "restarted server accepts a push")
    check(waitUntil({ events.last == .event(.push(commits: 4)) }), "restarted server delivers")
    server.stop()
}

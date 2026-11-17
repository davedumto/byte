import Foundation
import Network

/// Listens on 0.0.0.0:7420 for work events from the Mac and advertises itself with Bonjour as "Byte"
/// (_byte._tcp), so the Mac never needs the iPod's IP address (step 5, decisions 1A and 3A).
/// One request per connection, local-network peers only, a few connections at a time, short timeouts.
/// The listener only runs while the app is in the foreground; the view controller stops and starts it.
final class EventServer {
    static let defaultPort: UInt16 = 7420
    static let serviceName = "Byte"
    static let serviceType = "_byte._tcp"
    static let maxConnections = 4
    static let requestTimeout: TimeInterval = 5
    static let restartDelay: TimeInterval = 5

    private let port: UInt16
    private let advertise: Bool
    private let token: () -> String?
    private let onEvent: (ParsedEvent) -> Void   // called on the main queue
    private let log: (String) -> Void
    private let queue = DispatchQueue(label: "byte.events")

    // Touched on `queue` only.
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var wanted = false
    private var restartPending = false

    init(port: UInt16 = EventServer.defaultPort, advertise: Bool = true,
         token: @escaping () -> String? = { Token.read(from: Token.eventsPath) },
         log: @escaping (String) -> Void = { _ in },
         onEvent: @escaping (ParsedEvent) -> Void) {
        self.port = port
        self.advertise = advertise
        self.token = token
        self.log = log
        self.onEvent = onEvent
    }

    /// Safe to call repeatedly (e.g. on every return to the foreground).
    func start() { queue.async { self.wanted = true; self.startListener() } }

    func stop() {
        queue.async {
            self.wanted = false
            self.listener?.cancel(); self.listener = nil
            self.connections.values.forEach { $0.cancel() }; self.connections = [:]
        }
    }

    /// Called on `queue`, so tests can wait for the listener to be up.
    var onReady: (() -> Void)?

    // MARK: - Listener

    private func startListener() {
        guard wanted, listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true // relaunching right after a crash must not hit "address in use"
        do {
            let l = try NWListener(using: params, on: nwPort)
            if advertise { l.service = NWListener.Service(name: EventServer.serviceName, type: EventServer.serviceType) }
            l.stateUpdateHandler = { [weak self, weak l] state in self?.listenerChanged(state, l) }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            listener = l
            l.start(queue: queue)
        } catch {
            log("events: could not listen on \(port): \(error)")
            scheduleRestart()
        }
    }

    private func listenerChanged(_ state: NWListener.State, _ l: NWListener?) {
        switch state {
        case .ready:
            log("events: listening on \(port)")
            onReady?()
        case .failed(let error):
            log("events: listener failed: \(error)")
            l?.cancel()
            if listener === l { listener = nil }
            scheduleRestart()
        default:
            break
        }
    }

    private func scheduleRestart() {
        guard wanted, !restartPending else { return }
        restartPending = true
        queue.asyncAfter(deadline: .now() + EventServer.restartDelay) {
            self.restartPending = false
            self.startListener()
        }
    }

    // MARK: - Connections

    private func accept(_ c: NWConnection) {
        guard EventServer.isLocal(c.endpoint) else {
            log("events: refused a connection from outside the local network")
            return c.cancel()
        }
        guard connections.count < EventServer.maxConnections else { return c.cancel() }
        let id = ObjectIdentifier(c)
        connections[id] = c
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections[id] = nil
            default: break
            }
        }
        c.start(queue: queue)
        queue.asyncAfter(deadline: .now() + EventServer.requestTimeout) { [weak self] in
            guard self?.connections[id] != nil else { return }
            self?.finish(c, .error(408, "request took too long"))
        }
        read(c, buffer: Data())
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: HTTPParser.maxRequestBytes) { [weak self] data, _, isComplete, error in
            guard let self = self, self.connections[ObjectIdentifier(c)] != nil else { return }
            if error != nil { return c.cancel() }
            var buffer = buffer
            if let data = data { buffer.append(data) }
            switch HTTPParser.parse(buffer) {
            case .incomplete:
                if isComplete || buffer.count > HTTPParser.maxRequestBytes { return c.cancel() } // peer gave up mid-request
                self.read(c, buffer: buffer)
            case .invalid(let response):
                self.finish(c, response)
            case .complete(let request):
                let (response, event) = EventRouter.respond(to: request, expectedToken: self.token())
                if response.status == 401 || response.status == 503 { self.log("events: request refused (\(response.status))") }
                self.finish(c, response)
                if let event = event { DispatchQueue.main.async { self.onEvent(event) } }
            }
        }
    }

    private func finish(_ c: NWConnection, _ response: HTTPResponse) {
        connections[ObjectIdentifier(c)] = nil
        c.send(content: response.data, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: - Local network check

    /// Private, link-local and loopback addresses only (the spec exposes 7420 to the local Wi-Fi only).
    static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a): return isLocalIPv4(Array(a.rawValue))
        case .ipv6(let a): return isLocalIPv6(Array(a.rawValue))
        default: return false
        }
    }

    static func isLocalIPv4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 10 || b[0] == 127 ||
            (b[0] == 172 && (16...31).contains(b[1])) ||
            (b[0] == 192 && b[1] == 168) ||
            (b[0] == 169 && b[1] == 254)
    }

    static func isLocalIPv6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }          // ::1
        if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }                    // fe80::/10 link-local
        if (b[0] & 0xfe) == 0xfc { return true }                                    // fc00::/7 unique local
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff {    // ::ffff:a.b.c.d
            return isLocalIPv4(Array(b[12..<16]))
        }
        return false
    }
}

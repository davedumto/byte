import UIKit
import WebKit

/// Hosts the 3D world full screen in a WKWebView loaded from the app bundle, and wires up the window.byte bridge.
final class WorldViewController: UIViewController {
    /// The world's background (#171923), so launch and reloads never flash white.
    static let roomColor = UIColor(red: 0x17 / 255.0, green: 0x19 / 255.0, blue: 0x23 / 255.0, alpha: 1)
    /// Name of the message handler main.js posts to: webkit.messageHandlers.byte.
    static let handlerName = "byte"

    private var webView: WKWebView!
    private var bridge: WorldBridge!
    private var turns: TurnController!
    private var worldDirectory: URL?
    private var events: EventServer!
    private let reactor = EventReactor()

    // MARK: - Setup

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(self), name: WorldViewController.handlerName)
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = WorldViewController.roomColor
        webView.scrollView.backgroundColor = WorldViewController.roomColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.navigationDelegate = self
        self.webView = webView
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bridge = WorldBridge { [weak self] js in
            self?.webView.evaluateJavaScript(js) { _, error in
                if let error = error { Log.info("bridge call failed: \(error.localizedDescription)") }
            }
        }
        turns = TurnController(bridge: bridge, brain: LlamaBrain(), log: Log.info)
        startEvents()

        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        press.minimumPressDuration = 0.6
        press.cancelsTouchesInView = false // the world still gets every touch
        press.delegate = self
        webView.addGestureRecognizer(press)

        loadWorld()
    }

    private func loadWorld() {
        guard let dir = Bundle.main.url(forResource: "world", withExtension: nil) else {
            return showProblem("The world files are missing from the app.")
        }
        let index = dir.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else {
            return showProblem("world/index.html is missing from the app.")
        }
        worldDirectory = dir.resolvingSymlinksInPath() // /var vs /private/var must compare equal
        bridge.markNotReady()
        webView.loadFileURL(index, allowingReadAccessTo: dir)
        Log.info("loading world")
    }

    private func showProblem(_ text: String) {
        Log.info("problem: \(text)")
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
    }

    // MARK: - Push events from the Mac (step 5)

    /// Listens only while Byte is on screen: iOS suspends a background app, and a stale Bonjour
    /// advertisement would make the Mac wait for a pet that can't answer.
    private func startEvents() {
        events = EventServer(log: Log.info) { [weak self] parsed in self?.handle(parsed) }
        events.start()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillEnterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func appWillEnterForeground() { events.start() }
    @objc private func appDidEnterBackground() { events.stop() }

    private func handle(_ parsed: ParsedEvent) {
        Log.info("event: \(EventSchema.logText(parsed))") // type and count only, never repo or branch names
        guard case .event(let event) = parsed, let command = reactor.react(to: event) else { return }
        bridge.send(command)
    }

    // MARK: - Screen

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - About (long-press the mood chip)

    /// Asks the page where the mood chip is, in web view points. Read live so it follows the HUD's layout.
    private static let moodChipRectJS = """
    (function () {
      var label = document.getElementById('moodLabel');
      var chip = label && label.closest('.chip');
      if (!chip) return null;
      var r = chip.getBoundingClientRect();
      return [r.left, r.top, r.width, r.height];
    })()
    """

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, presentedViewController == nil else { return }
        let point = gesture.location(in: webView)
        webView.evaluateJavaScript(WorldViewController.moodChipRectJS) { [weak self] result, _ in
            guard let self = self,
                  let n = result as? [NSNumber], n.count == 4 else { return }
            let chip = CGRect(x: n[0].doubleValue, y: n[1].doubleValue, width: n[2].doubleValue, height: n[3].doubleValue)
            guard chip.insetBy(dx: -8, dy: -8).contains(point) else { return } // a little slack for fingers
            self.presentAbout()
        }
    }

    private func presentAbout() {
        guard presentedViewController == nil else { return }
        let nav = UINavigationController(rootViewController: AboutViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
}

// MARK: - World -> app messages

extension WorldViewController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == WorldViewController.handlerName else { return }
        guard let parsed = WorldMessage.parse(message.body) else {
            return Log.info("ignored world message: \(type(of: message.body))")
        }
        if parsed == .ready { Log.info("world ready") }
        turns.handle(parsed)
    }
}

// MARK: - Navigation: only the bundled world may load

extension WorldViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, url.isFileURL, let dir = worldDirectory,
              url.resolvingSymlinksInPath().path.hasPrefix(dir.path + "/") else { // "/" so world-evil/ can't match
            Log.info("blocked navigation to \(action.request.url?.scheme ?? "?") URL")
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.info("world navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.info("world failed to load: \(error.localizedDescription)")
    }

    /// iOS can kill the web content process under memory pressure (likely once the brain is loaded).
    /// Drop the current turn and reload the world; commands queue until it posts ready again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.info("web content process terminated; reloading world")
        turns.reset()
        loadWorld()
    }
}

extension WorldViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true // never steal touches from the world's own drag/orbit handling
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle with the view controller.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

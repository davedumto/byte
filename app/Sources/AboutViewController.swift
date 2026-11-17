import UIKit

/// Credits the spec requires to stay visible in the app (docs/TECHNICAL.md, "Credits").
/// Opened by long-pressing the mood chip.
final class AboutViewController: UIViewController {
    private struct Credit {
        let text: String
        let links: [(phrase: String, url: String)]
    }

    private static let credits: [Credit] = [
        Credit(text: "Robot: “Mini_bot” by allzeronce, licensed CC BY 4.0, from Sketchfab. Animated and recoloured for Byte.",
               links: [("“Mini_bot”", "https://sketchfab.com/3d-models/mini-bot-bb951fb4e285427cbbf6b9241eac78cb"),
                       ("allzeronce", "https://sketchfab.com/allzeronce"),
                       ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")]),
        // Decision 2026-11-16, 4A: the brain is Qwen2.5-Coder, so Qwen is credited instead of Llama.
        Credit(text: "Brain: Qwen2.5-Coder 0.5B Instruct by the Qwen team, Alibaba Cloud, licensed Apache 2.0. Runs on the device with llama.cpp (MIT).",
               links: [("Qwen2.5-Coder 0.5B Instruct", "https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct"),
                       ("Apache 2.0", "https://www.apache.org/licenses/LICENSE-2.0"),
                       ("llama.cpp", "https://github.com/ggml-org/llama.cpp")]),
        Credit(text: "Fonts: Inter and Space Grotesk, SIL Open Font License 1.1.",
               links: [("SIL Open Font License 1.1", "https://openfontlicense.org")]),
        Credit(text: "Room: original, built for Byte.", links: [])
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About Byte"
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = WorldViewController.roomColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))

        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.attributedText = AboutViewController.body()
        textView.linkTextAttributes = [.foregroundColor: UIColor(red: 0x59 / 255.0, green: 0xF0 / 255.0, blue: 0xB5 / 255.0, alpha: 1)]
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
    }

    @objc private func done() { dismiss(animated: true) }

    private static func body() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 12
        let base: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor(white: 0.93, alpha: 1), .paragraphStyle: paragraph
        ]
        for credit in credits {
            let piece = NSMutableAttributedString(string: credit.text + "\n", attributes: base)
            for link in credit.links {
                let range = (credit.text as NSString).range(of: link.phrase)
                if range.location != NSNotFound, let url = URL(string: link.url) { piece.addAttribute(.link, value: url, range: range) }
            }
            out.append(piece)
        }
        return out
    }
}

import ControlVCore
import SwiftUI
import UIKit

/// Control-V Keyboard: the iOS equivalent of the Mac global shortcut.
///
/// Flow (Grammarly-style in-place replacement):
/// 1. User selects text in ANY app (or finishes typing a message)
/// 2. Switches to the Control-V keyboard (globe key)
/// 3. Taps "Translate" → the keyboard reads the selection (or the text
///    before the cursor), calls the backend, and REPLACES it in-place
/// 4. Switches back to their normal keyboard
///
/// Requires "Allow Full Access" (Settings → Keyboard) for network calls.
final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardPanelView>?
    private let panelHeight: CGFloat = 260

    override func viewDidLoad() {
        super.viewDidLoad()

        let panel = KeyboardPanelView(
            hasFullAccess: hasFullAccess,
            actions: KeyboardActions(
                readSelectedText: { [weak self] in
                    self?.textDocumentProxy.selectedText
                },
                readTypedText: { [weak self] in
                    self?.textDocumentProxy.documentContextBeforeInput
                },
                replaceSelectedText: { [weak self] translation in
                    // insertText replaces the active selection in standard
                    // UIKit text fields/views.
                    self?.textDocumentProxy.insertText(translation)
                },
                replaceTypedText: { [weak self] original, translation in
                    guard let proxy = self?.textDocumentProxy else { return }
                    guard !original.isEmpty else {
                        proxy.insertText(translation)
                        return
                    }

                    // First backspace, then VERIFY: if the host had a selection it
                    // didn't expose via selectedText, that first deleteBackward
                    // consumed the whole selection instead of one grapheme. In that
                    // case, stop deleting and just insert — never chew through
                    // text we didn't capture.
                    proxy.deleteBackward()
                    let expectedAfterFirst = String(original.dropLast())
                    let contextNow = proxy.documentContextBeforeInput ?? ""
                    guard contextNow.hasSuffix(expectedAfterFirst) || expectedAfterFirst.isEmpty else {
                        proxy.insertText(translation)
                        return
                    }

                    for _ in 0..<expectedAfterFirst.count {
                        proxy.deleteBackward()
                    }
                    proxy.insertText(translation)
                },
                insertText: { [weak self] text in
                    self?.textDocumentProxy.insertText(text)
                },
                switchKeyboard: { [weak self] in
                    self?.advanceToNextInputMode()
                }
            )
        )

        let host = UIHostingController(rootView: panel)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Give the keyboard a fixed height.
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: panelHeight)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true

        hostingController = host
    }
}

/// Callbacks bridging SwiftUI panel → UITextDocumentProxy.
struct KeyboardActions {
    let readSelectedText: () -> String?
    let readTypedText: () -> String?
    let replaceSelectedText: (String) -> Void
    let replaceTypedText: (_ original: String, _ translation: String) -> Void
    let insertText: (String) -> Void
    let switchKeyboard: () -> Void
}

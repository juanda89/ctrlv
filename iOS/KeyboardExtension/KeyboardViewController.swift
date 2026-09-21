import ControlVCore
import SwiftUI
import UIKit

/// Control-V Keyboard: the system keyboard's layout with a Control-V key.
///
/// Flow:
/// 1. The user types with Control-V the way they would with any keyboard.
/// 2. They select text (or just finish typing) and tap **Translate**.
/// 3. The keyboard reads the selection (or the text before the cursor), calls
///    the backend, and replaces it in place.
///
/// Requires "Allow Full Access" (Settings → Keyboard) for network calls; the
/// keys work without it, only translation is blocked.
final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardPanelView>?
    /// The rows plus the air above the first one; iOS adds its own globe and
    /// dictation bar underneath, as it does for its keyboard.
    private let panelHeight: CGFloat = KeyboardPanelView.bandHeight + KeyboardLayoutView.height + KeyboardPanelView.bottomPadding

    override func loadView() {
        // UIDevice.playInputClick() only sounds when the input view opts in.
        view = ClickingInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Let the height constraint below size the input view. Without this
        // the system first lays the keyboard out at its own default height and
        // resizes it a frame later, which shows as the keyboard jumping into
        // place when the user switches to Control-V.
        inputView?.allowsSelfSizing = true

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
                deleteBackward: { [weak self] in
                    self?.textDocumentProxy.deleteBackward()
                },
                contextBeforeInput: { [weak self] in
                    self?.textDocumentProxy.documentContextBeforeInput
                },
                switchKeyboard: { [weak self] in
                    self?.advanceToNextInputMode()
                },
                showsKeyboardSwitch: needsInputModeSwitchKey
            )
        )

        // Key previews rise above the top row, past the input view's edge.
        view.clipsToBounds = false
        let host = UIHostingController(rootView: panel)
        // The keys must not move with the host's safe area: while the input
        // view is being positioned its insets are not the keyboard's.
        host.safeAreaRegions = []
        host.view.frame = view.bounds
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Give the keyboard a fixed height. Just below required so the
        // system's own constraints on the input view never conflict.
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: panelHeight)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true

        hostingController = host
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Settle the layout before the first frame is shown.
        view.layoutIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The app cannot ask iOS whether this keyboard is installed, so record
        // the fact here; the setup screen reads it to show live status.
        SetupState.markKeyboardActive(hasFullAccess: hasFullAccess)
    }
}

/// Keyboard clicks play only for input views that adopt the audio feedback
/// protocol (and, per Apple, only with Full Access).
final class ClickingInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// Callbacks bridging SwiftUI keys → UITextDocumentProxy.
struct KeyboardActions {
    let readSelectedText: () -> String?
    let readTypedText: () -> String?
    let replaceSelectedText: (String) -> Void
    let replaceTypedText: (_ original: String, _ translation: String) -> Void
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let contextBeforeInput: () -> String?
    let switchKeyboard: () -> Void
    /// False when Control-V is the only keyboard installed: iOS then hides its
    /// own globe key, and showing ours would be a dead end.
    var showsKeyboardSwitch: Bool = true
}

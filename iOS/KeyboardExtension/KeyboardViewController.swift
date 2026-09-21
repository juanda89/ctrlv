import ControlVCore
import KeyboardKit
import SwiftUI
import UIKit

/// Control-V Keyboard: KeyboardKit's engine, the system keyboard's look, and
/// one extra key. Tapping the Control-V key translates what was typed or
/// selected and replaces it in place; a long press picks language and tone.
///
/// Requires "Allow Full Access" (Settings → Keyboard) for network calls; the
/// keys work without it, only translation is blocked.
final class KeyboardViewController: KeyboardInputViewController {
    private lazy var flow = TranslateFlow(hasFullAccess: hasFullAccess, actions: makeActions())

    override func viewDidLoad() {
        super.viewDidLoad()
        setup(for: .controlV) { [weak self] result in
            guard let self, case .success = result else { return }
            self.configure()
        }
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            ControlVKeyboardView(
                services: controller.services,
                state: controller.state,
                flow: self?.flow ?? TranslateFlow(hasFullAccess: false, actions: .noop)
            )
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The app cannot ask iOS whether this keyboard is installed, so record
        // the fact here; the setup screen reads it to show live status.
        SetupState.markKeyboardActive(hasFullAccess: hasFullAccess)
    }

    private func configure() {
        let context = state.keyboardContext
        context.setIsLiquidGlassEnabled(context.isLiquidGlassAvailable)
        services.layoutService = ControlVLayoutService(language: .current)
        services.actionHandler = ControlVActionHandler(controller: self, flow: flow)
    }

    private func makeActions() -> KeyboardActions {
        KeyboardActions(
            readSelectedText: { [weak self] in self?.textDocumentProxy.selectedText },
            readTypedText: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput },
            replaceSelectedText: { [weak self] translation in
                // insertText replaces the active selection in standard UIKit text views.
                self?.textDocumentProxy.insertText(translation)
            },
            replaceTypedText: { [weak self] original, translation in
                guard let proxy = self?.textDocumentProxy else { return }
                guard !original.isEmpty else { proxy.insertText(translation); return }
                // First backspace, then VERIFY: if the host had a selection it
                // did not expose via selectedText, that first deleteBackward
                // consumed the whole selection instead of one grapheme. Then
                // stop deleting and just insert; never chew through text that
                // was not captured.
                proxy.deleteBackward()
                let expectedAfterFirst = String(original.dropLast())
                let contextNow = proxy.documentContextBeforeInput ?? ""
                guard contextNow.hasSuffix(expectedAfterFirst) || expectedAfterFirst.isEmpty else {
                    proxy.insertText(translation)
                    return
                }
                for _ in 0..<expectedAfterFirst.count { proxy.deleteBackward() }
                proxy.insertText(translation)
            },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            contextBeforeInput: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput }
        )
    }
}

extension KeyboardApp {
    static let controlV = KeyboardApp(
        name: "Control-V",
        appGroupId: SetupState.appGroup,
        locales: [.spanish, .english]
    )
}

extension KeyboardActions {
    static let noop = KeyboardActions(
        readSelectedText: { nil }, readTypedText: { nil }, replaceSelectedText: { _ in },
        replaceTypedText: { _, _ in }, insertText: { _ in }, deleteBackward: {}, contextBeforeInput: { nil }
    )
}

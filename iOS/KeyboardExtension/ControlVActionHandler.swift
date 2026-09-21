import KeyboardKit

/// KeyboardKit's standard action handler plus the Control-V key: a tap
/// translates, a long press shows the language and tone chips.
final class ControlVActionHandler: KeyboardAction.StandardActionHandler {
    private let flow: TranslateFlow

    init(controller: KeyboardInputViewController, flow: TranslateFlow) {
        self.flow = flow
        super.init(
            controller: controller,
            keyboardContext: controller.state.keyboardContext,
            keyboardBehavior: controller.services.keyboardBehavior,
            autocompleteContext: controller.state.autocompleteContext,
            autocompleteService: controller.services.autocompleteService,
            emojiContext: controller.state.emojiContext,
            feedbackContext: controller.state.feedbackContext,
            feedbackService: controller.services.feedbackService,
            spaceDragGestureHandler: controller.services.spaceDragGestureHandler
        )
    }

    override func action(for gesture: Keyboard.Gesture, on action: KeyboardAction) -> KeyboardAction.GestureAction? {
        guard action == ControlVLayoutService.translateAction else {
            return super.action(for: gesture, on: action)
        }
        switch gesture {
        case .release: return { [flow] _ in Task { @MainActor in flow.translate() } }
        case .longPress: return { [flow] _ in Task { @MainActor in flow.toggleOptions() } }
        default: return nil
        }
    }
}

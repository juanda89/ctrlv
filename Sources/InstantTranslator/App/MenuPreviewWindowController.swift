import AppKit
import SwiftUI

enum MenuPreviewScenario: String {
    case current
    case trial
    case active
    case expired
    case invalid

    static func fromEnvironment() -> MenuPreviewScenario? {
        let env = ProcessInfo.processInfo.environment
        guard env["CTRLV_DEBUG_MENU_WINDOW"] == "1" else { return nil }
        let rawValue = env["CTRLV_DEBUG_MENU_SCENARIO"]?.lowercased() ?? "trial"
        return MenuPreviewScenario(rawValue: rawValue) ?? .trial
    }

    static func fromRawValue(_ rawValue: String?) -> MenuPreviewScenario? {
        guard let rawValue else { return nil }
        return MenuPreviewScenario(rawValue: rawValue.lowercased())
    }
}

enum MenuPreviewAppearance: String {
    case system
    case light
    case dark

    static func fromEnvironment() -> MenuPreviewAppearance {
        let env = ProcessInfo.processInfo.environment
        let rawValue = env["CTRLV_DEBUG_MENU_APPEARANCE"]?.lowercased() ?? "system"
        return MenuPreviewAppearance(rawValue: rawValue) ?? .system
    }

    static func fromRawValue(_ rawValue: String?) -> MenuPreviewAppearance? {
        guard let rawValue else { return nil }
        return MenuPreviewAppearance(rawValue: rawValue.lowercased())
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

struct MenuPreviewRequest {
    let scenario: MenuPreviewScenario
    let appearance: MenuPreviewAppearance
    let snapshotOutputPath: String?

    static func fromProcessInfo() -> MenuPreviewRequest? {
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments

        let snapshotOutputPath = argumentValue("--render-menu-snapshot", in: args)
            ?? env["CTRLV_RENDER_MENU_SNAPSHOT"]
        let shouldOpenPreviewWindow = args.contains("--debug-menu-window")
            || env["CTRLV_DEBUG_MENU_WINDOW"] == "1"
        let scenario = MenuPreviewScenario.fromRawValue(argumentValue("--menu-scenario", in: args))
            ?? MenuPreviewScenario.fromEnvironment()
            ?? MenuPreviewScenario.fromRawValue(env["CTRLV_DEBUG_MENU_SCENARIO"])
            ?? .trial
        let appearance = MenuPreviewAppearance.fromRawValue(argumentValue("--menu-appearance", in: args))
            ?? MenuPreviewAppearance.fromEnvironment()

        guard shouldOpenPreviewWindow || snapshotOutputPath != nil else {
            return nil
        }

        return MenuPreviewRequest(
            scenario: scenario,
            appearance: appearance,
            snapshotOutputPath: snapshotOutputPath
        )
    }

    private static func argumentValue(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }
}

@MainActor
final class MenuPreviewWindowController: NSWindowController {
    init(rootView: MenuBarView, appearance: MenuPreviewAppearance) {
        let contentController = NativePopoverHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: contentController)
        window.title = "ctrl+v Menu Preview"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.setContentSize(NSSize(width: 336, height: 560))
        window.appearance = appearance.nsAppearance
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

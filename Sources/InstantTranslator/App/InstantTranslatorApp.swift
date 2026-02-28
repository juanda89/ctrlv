import AppKit
import SwiftUI
import TelemetryDeck

@main
struct InstantTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let config = TelemetryDeck.Config(appID: "EAF0D438-86C4-47B0-B489-FD8ED54ECB89")
        TelemetryDeck.initialize(config: config)
    }

    var body: some Scene {
        Settings {
            HiddenSettingsView()
                .frame(width: 1, height: 1)
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

private struct HiddenSettingsView: View {
    var body: some View {
        Color.clear
            .onAppear {
                DispatchQueue.main.async {
                    for window in NSApp.windows where window.title.localizedCaseInsensitiveContains("settings") {
                        window.orderOut(nil)
                        window.close()
                    }
                }
            }
    }
}

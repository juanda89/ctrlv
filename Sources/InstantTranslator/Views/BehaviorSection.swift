import SwiftUI

@MainActor
struct BehaviorSection: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var translatorVM: TranslatorViewModel
    @State private var isAccessibilityGranted = false
    @State private var pollingTimer: Timer?
    @State private var isShortcutSettingsPresented = false

    var body: some View {
        VStack(spacing: 8) {
            shortcutAndPasteCard
            accessibilityCard
        }
        .onAppear {
            checkAccessibility()
            if !isAccessibilityGranted {
                startPolling()
            }
        }
        .onDisappear {
            stopPolling()
        }
    }

    private var shortcutAndPasteCard: some View {
        MenuCard {
            Button {
                isShortcutSettingsPresented = true
            } label: {
                HStack {
                    NativeSectionLabel(systemName: "keyboard", tint: .gray, title: "Shortcut")

                    Spacer()

                    HStack(spacing: 6) {
                        ShortcutBadge(keys: settingsVM.shortcutKeyCaps)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuTheme.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                NativeSectionLabel(systemName: "arrow.left.arrow.right.square", tint: .teal, title: "Auto-paste")

                Spacer()

                Toggle("", isOn: $settingsVM.settings.autoPaste)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .sheet(isPresented: $isShortcutSettingsPresented) {
            ShortcutSettingsView(settingsVM: settingsVM) {
                translatorVM.refreshHotkeyRegistration()
            }
        }
    }

    private var accessibilityCard: some View {
        MenuCard {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isAccessibilityGranted ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(isAccessibilityGranted ? "Accessibility: Granted" : "Accessibility: Not Granted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if !isAccessibilityGranted {
                    HStack(spacing: 4) {
                        Button("Reset") {
                            AccessibilityService.resetAndReRequest()
                            startPolling()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(.orange)

                        Button("Open Settings") {
                            AccessibilityService.openAccessibilitySettings()
                            startPolling()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            if !isAccessibilityGranted {
                Text("If you already granted permission but it still shows Not Granted, click Reset. This happens when the app is rebuilt with a new code signature.")
                    .font(.footnote)
                    .foregroundStyle(MenuTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func checkAccessibility() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    private func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                checkAccessibility()
                if isAccessibilityGranted {
                    stopPolling()
                }
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

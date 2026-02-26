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
            providerAndKeysCard
            accessibilityCard
            debugCard
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
                    HStack(spacing: 8) {
                        IconBubble(systemName: "keyboard", tint: .gray)
                        Text("Shortcut")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ShortcutBadge(keys: settingsVM.shortcutKeyCaps)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                HStack(spacing: 8) {
                    IconBubble(systemName: "arrow.left.arrow.right.square", tint: .teal)
                    Text("Auto-paste")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

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

    private var providerAndKeysCard: some View {
        MenuCard {
            HStack {
                HStack(spacing: 8) {
                    IconBubble(systemName: "network", tint: .purple)
                    Text("Provider")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $settingsVM.settings.selectedProvider) {
                    ForEach(ProviderType.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 132)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    IconBubble(systemName: "key.fill", tint: .orange)
                    Text("API Key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                APIKeyField(apiKey: $settingsVM.apiKey)
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
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
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var debugCard: some View {
        MenuCard {
            Text("Debug")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Hotkey events: \(translatorVM.debugHotkeyTriggerCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Last trigger: \(lastTriggerText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("Last stage: \(translatorVM.debugLastStage)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("Last error: \(translatorVM.lastError ?? "none")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            Text("Event log")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(translatorVM.debugEvents.prefix(8).enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
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

    private var lastTriggerText: String {
        guard let timestamp = translatorVM.debugLastTriggerAt else {
            return "none"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return "\(translatorVM.debugLastTriggerSource) at \(formatter.string(from: timestamp))"
    }
}

import SwiftUI

@MainActor
struct BehaviorSection: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var translatorVM: TranslatorViewModel
    @Bindable var updateService: UpdateService
    @State private var isAccessibilityGranted = false
    @State private var pollingTimer: Timer?
    @State private var isShortcutSettingsPresented = false
    @State private var isProviderHelpPresented = false
    @State private var isEditingAPIKey = false
    @State private var draftAPIKey = ""
    @State private var isCheckingProviderStatus = false
    @State private var apiKeyValidationByProvider: [ProviderType: APIKeyFieldValidationState] = [:]

    private let apiKeyValidationService = APIKeyValidationService()

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
            syncAPIKeyDraft()
        }
        .onDisappear {
            stopPolling()
        }
        .onChange(of: settingsVM.settings.selectedProvider, initial: false) { _, _ in
            syncAPIKeyDraft()
        }
        .sheet(isPresented: $isProviderHelpPresented) {
            APIKeyTutorialSheet(provider: settingsVM.settings.selectedProvider)
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
                    IconBubble(systemName: "sparkles", tint: .purple)
                    Text("LLM Provider")
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
                APIKeyField(
                    storedKey: settingsVM.apiKeyForSelectedProvider(),
                    draftKey: $draftAPIKey,
                    placeholder: settingsVM.apiKeyPlaceholder,
                    isEditing: isEditingAPIKey,
                    validationState: validationStateForSelectedProvider(),
                    showsStatus: false,
                    onEdit: beginEditingAPIKey,
                    onCancel: cancelEditingAPIKey,
                    onSave: {
                        Task { @MainActor in
                            await saveAPIKeyChanges()
                        }
                    }
                )

                HStack(spacing: 8) {
                    providerStatusButton
                    Spacer()
                    Button {
                        isProviderHelpPresented = true
                    } label: {
                        Text(settingsVM.settings.selectedProvider.apiKeyHelpTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
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

            Text(updateService.debugSummaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(updateService.debugDetailsLine)
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

            HStack(spacing: 6) {
                Button("Test Island") {
                    translatorVM.debugPreviewTranslationIsland()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
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

    private func beginEditingAPIKey() {
        isEditingAPIKey = true
        draftAPIKey = settingsVM.apiKeyForSelectedProvider()
    }

    private func cancelEditingAPIKey() {
        isEditingAPIKey = false
        draftAPIKey = settingsVM.apiKeyForSelectedProvider()
    }

    private func syncAPIKeyDraft() {
        isEditingAPIKey = false
        draftAPIKey = settingsVM.apiKeyForSelectedProvider()
    }

    private func saveAPIKeyChanges() async {
        let provider = settingsVM.settings.selectedProvider
        let newValue = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentValue = settingsVM.apiKey(for: provider)

        guard newValue != currentValue else {
            isEditingAPIKey = false
            return
        }

        if newValue.isEmpty {
            settingsVM.setAPIKey("", for: provider)
            apiKeyValidationByProvider[provider] = APIKeyFieldValidationState.none
            translatorVM.clearProviderRuntimeStatus(for: provider)
            isEditingAPIKey = false
            return
        }

        apiKeyValidationByProvider[provider] = .checking
        let result = await apiKeyValidationService.validate(apiKey: newValue, for: provider)

        switch result.outcome {
        case .valid, .rateLimited:
            settingsVM.setAPIKey(newValue, for: provider)
            apiKeyValidationByProvider[provider] = .valid(result.message)
            // New key clears old runtime status for this app session.
            translatorVM.clearProviderRuntimeStatus(for: provider)
            isEditingAPIKey = false
        case .invalid, .networkError:
            apiKeyValidationByProvider[provider] = .invalid(result.message)
            translatorVM.updateProviderRuntimeStatus(from: result, for: provider)
        }
    }

    private func validationStateForSelectedProvider() -> APIKeyFieldValidationState {
        let provider = settingsVM.settings.selectedProvider
        return apiKeyValidationByProvider[provider] ?? .none
    }

    private var providerStatusButton: some View {
        let style = providerStatusStyle

        return Button {
            Task { @MainActor in
                await refreshSelectedProviderStatus()
            }
        } label: {
            HStack(spacing: 5) {
                if isCheckingProviderStatus {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(style.tint)
                        .frame(width: 6, height: 6)
                }
                Text(style.text)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCheckingProviderStatus)
    }

    private var providerStatusStyle: (text: String, tint: Color, background: Color) {
        let provider = settingsVM.settings.selectedProvider
        let hasKey = !settingsVM.apiKey(for: provider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        if isCheckingProviderStatus {
            return ("Status: Checking...", .secondary, Color.primary.opacity(0.08))
        }

        guard hasKey else {
            return ("Status: No key", .secondary, Color.primary.opacity(0.08))
        }

        switch translatorVM.providerRuntimeStatus(for: provider) {
        case .rateLimited:
            return ("Status: Rate limited", .red, .red.opacity(0.12))
        case .error:
            return ("Status: Error", .red, .red.opacity(0.12))
        case .ok:
            return ("Status: OK", .green, .green.opacity(0.12))
        case .idle:
            return ("Status: OK", .green, .green.opacity(0.12))
        }
    }

    private func refreshSelectedProviderStatus() async {
        let provider = settingsVM.settings.selectedProvider
        let key = settingsVM.apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            translatorVM.clearProviderRuntimeStatus(for: provider)
            return
        }

        isCheckingProviderStatus = true
        defer { isCheckingProviderStatus = false }

        let result = await apiKeyValidationService.validate(apiKey: key, for: provider)
        translatorVM.updateProviderRuntimeStatus(from: result, for: provider)

        switch result.outcome {
        case .valid:
            apiKeyValidationByProvider[provider] = .valid(result.message)
        case .rateLimited:
            apiKeyValidationByProvider[provider] = .invalid(result.message)
        case .invalid, .networkError:
            apiKeyValidationByProvider[provider] = .invalid(result.message)
        }
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

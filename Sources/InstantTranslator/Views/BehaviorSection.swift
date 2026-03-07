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

    private var providerAndKeysCard: some View {
        MenuCard {
            HStack {
                NativeSectionLabel(systemName: "sparkles", tint: .purple, title: "LLM Provider")

                Spacer()

                NativeControlSurface(cornerRadius: 11, horizontalPadding: 8, verticalPadding: 4) {
                    Picker("", selection: $settingsVM.settings.selectedProvider) {
                        ForEach(ProviderType.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 124)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
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
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(MenuTheme.tertiaryText)
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
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.tint.opacity(0.18), lineWidth: 1)
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
            return ("Status: Checking...", .secondary, MenuTheme.controlFill)
        }

        guard hasKey else {
            return ("Status: No key", .secondary, MenuTheme.controlFill)
        }

        switch translatorVM.providerRuntimeStatus(for: provider) {
        case .rateLimited:
            return ("Status: Rate limited", .red, MenuTheme.tintedSurface(.red))
        case .error:
            return ("Status: Error", .red, MenuTheme.tintedSurface(.red))
        case .ok:
            return ("Status: OK", .green, MenuTheme.tintedSurface(.green))
        case .idle:
            return ("Status: OK", .green, MenuTheme.tintedSurface(.green))
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

}

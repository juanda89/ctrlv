import SwiftUI

@MainActor
struct DebugSheet: View {
    @Bindable var translatorVM: TranslatorViewModel
    @Bindable var updateService: UpdateService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Debug")
                    .font(.system(size: 18, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // MARK: - Telemetry

            GroupBox("TelemetryDeck") {
                VStack(alignment: .leading, spacing: 4) {
                    debugRow("Configured", value: TelemetryService.isConfigured ? "Yes" : "No",
                             tint: TelemetryService.isConfigured ? .green : .red)
                    debugRow("App ID", value: String(TelemetryService.appID.prefix(8)) + "...")
                    debugRow("Signals sent", value: "\(TelemetryService.signalsSentCount)")

                    if let lastSignal = TelemetryService.lastSignalName {
                        debugRow("Last signal", value: lastSignal)
                    }

                    if let lastAt = TelemetryService.lastSignalAt {
                        debugRow("Last sent at", value: timeString(lastAt))
                    }

                    HStack(spacing: 6) {
                        Button("Send Test Ping") {
                            TelemetryService.sendTestPing()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Text("Check TelemetryDeck dashboard for 'Debug.testPing'")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // MARK: - Translation Flow

            GroupBox("Translation Flow") {
                VStack(alignment: .leading, spacing: 4) {
                    debugRow("Hotkey events", value: "\(translatorVM.debugHotkeyTriggerCount)")
                    debugRow("Last trigger", value: lastTriggerText)
                    debugRow("Last stage", value: translatorVM.debugLastStage)
                    debugRow("Last error", value: translatorVM.lastError ?? "none")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // MARK: - Updates

            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 4) {
                    debugRow("Summary", value: updateService.debugSummaryLine)
                    debugRow("Details", value: updateService.debugDetailsLine)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // MARK: - Event Log

            GroupBox("Event Log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if translatorVM.debugEvents.isEmpty {
                            Text("No events yet")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array(translatorVM.debugEvents.prefix(20).enumerated()), id: \.offset) { _, event in
                                Text(event)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(4)
            }

            // MARK: - Actions

            HStack(spacing: 6) {
                Button("Test Island") {
                    translatorVM.debugPreviewTranslationIsland()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Trigger Translation") {
                    translatorVM.debugTriggerTranslationFromUI()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private func debugRow(_ label: String, value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
            }

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var lastTriggerText: String {
        guard let timestamp = translatorVM.debugLastTriggerAt else {
            return "none"
        }
        return "\(translatorVM.debugLastTriggerSource) at \(timeString(timestamp))"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

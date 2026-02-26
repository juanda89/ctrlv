import AppKit
import Foundation
import Observation
import Sparkle

enum UpdateInstallFailureKind: String {
    case permissionDenied
    case installerConnectionInvalidated
    case signatureValidation
    case network
    case unknown
}

@MainActor
@Observable
final class UpdateService: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @ObservationIgnored
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    @ObservationIgnored
    private var didRunLaunchCheck = false
    @ObservationIgnored
    private var latestCheckWasUserInitiated = false

    private(set) var lastUpdateErrorSummary: String?
    private(set) var lastUpdateErrorDetails: String?
    private(set) var lastUpdateErrorCode: String?
    private(set) var lastUpdateFailureDate: Date?
    private(set) var lastFailureKind: UpdateInstallFailureKind?
    var isShowingManualUpdateFallback = false

    override init() {
        super.init()
        _ = updaterController
    }

    func checkForUpdates() {
        latestCheckWasUserInitiated = true
        updaterController.checkForUpdates(nil)
    }

    /// Runs a background check once per app launch, so users can get an automatic
    /// "new version available" prompt without opening the menu manually.
    func checkForUpdatesAtLaunchIfEnabled() {
        guard !didRunLaunchCheck else { return }
        guard updaterController.updater.automaticallyChecksForUpdates else { return }
        guard !updaterController.updater.sessionInProgress else { return }
        didRunLaunchCheck = true
        latestCheckWasUserInitiated = false
        updaterController.updater.checkForUpdatesInBackground()
    }

    func dismissManualUpdateFallback() {
        isShowingManualUpdateFallback = false
    }

    func openLatestDMG() {
        guard let url = URL(string: "https://github.com/juanda89/ctrlv/releases/latest/download/ctrlv-latest.dmg") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openInstallGuide() {
        guard let url = Constants.manualUpdateURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyDiagnosticsToClipboard() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let dateText = lastUpdateFailureDate.map { formatter.string(from: $0) } ?? "none"
        let summary = lastUpdateErrorSummary ?? "none"
        let details = lastUpdateErrorDetails ?? "none"
        let code = lastUpdateErrorCode ?? "none"
        let failureKind = lastFailureKind?.rawValue ?? "none"

        let diagnostics = """
        ctrl+v Sparkle diagnostics
        - failure_kind: \(failureKind)
        - summary: \(summary)
        - code: \(code)
        - date: \(dateText)
        - details: \(details)
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostics, forType: .string)
    }

    var debugSummaryLine: String {
        if let summary = lastUpdateErrorSummary {
            return "Update error: \(summary)"
        }
        return "Update error: none"
    }

    var debugDetailsLine: String {
        guard let details = lastUpdateErrorDetails else {
            return "Update details: none"
        }
        let compact = details.replacingOccurrences(of: "\n", with: " | ")
        return "Update details: \(compact)"
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated func standardUserDriverWillShowModalAlert() {
        // This is a menu bar app (LSUIElement). Bring it forward so the Sparkle
        // update alert is immediately visible to the user.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        Task { @MainActor [weak self] in
            self?.captureUpdateFailure(error as NSError)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.captureUpdateFailure(error as NSError)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.latestCheckWasUserInitiated = false }
            guard let error else { return }
            self.captureUpdateFailure(error as NSError)
        }
    }

    // MARK: - Private

    private func captureUpdateFailure(_ error: NSError) {
        if isIgnorableSparkleError(error) {
            return
        }

        let kind = classify(error)
        lastFailureKind = kind
        lastUpdateFailureDate = Date()
        lastUpdateErrorSummary = summaryMessage(for: kind)
        lastUpdateErrorDetails = flattenedErrorDetails(error)
        lastUpdateErrorCode = "\(error.domain)#\(error.code)"

        if latestCheckWasUserInitiated && shouldShowManualFallback(for: kind) {
            isShowingManualUpdateFallback = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isIgnorableSparkleError(_ error: NSError) -> Bool {
        // Sparkle uses these two codes for normal user flows.
        if error.code == 1001 || error.code == 4007 {
            return true
        }
        return false
    }

    private func shouldShowManualFallback(for kind: UpdateInstallFailureKind) -> Bool {
        switch kind {
        case .permissionDenied, .installerConnectionInvalidated, .signatureValidation, .network, .unknown:
            return true
        }
    }

    private func summaryMessage(for kind: UpdateInstallFailureKind) -> String {
        switch kind {
        case .permissionDenied:
            return "Automatic install failed due to permissions or app location."
        case .installerConnectionInvalidated:
            return "Sparkle installer connection failed during update install."
        case .signatureValidation:
            return "Downloaded update failed signature or validation checks."
        case .network:
            return "Update download failed due to a network issue."
        case .unknown:
            return "Automatic update failed unexpectedly."
        }
    }

    private func classify(_ error: NSError) -> UpdateInstallFailureKind {
        let fullText = [
            error.localizedDescription,
            error.localizedFailureReason ?? "",
            error.localizedRecoverySuggestion ?? "",
            flattenedErrorDetails(error)
        ]
        .joined(separator: " ")
        .lowercased()

        if error.domain == NSURLErrorDomain ||
            fullText.contains("timed out") ||
            fullText.contains("network") ||
            fullText.contains("could not connect") {
            return .network
        }

        if fullText.contains("permission") ||
            fullText.contains("not permitted") ||
            fullText.contains("write") ||
            fullText.contains("app management") ||
            fullText.contains("doesn't exist") ||
            fullText.contains("no such file") {
            return .permissionDenied
        }

        if fullText.contains("running the updater") ||
            fullText.contains("remote port connection was invalidated") ||
            fullText.contains("installer connection") {
            return .installerConnectionInvalidated
        }

        if fullText.contains("signature") ||
            fullText.contains("signed") ||
            fullText.contains("validation") ||
            fullText.contains("code signing") {
            return .signatureValidation
        }

        return .unknown
    }

    private func flattenedErrorDetails(_ error: NSError) -> String {
        var lines: [String] = []
        var currentError: NSError? = error
        var guardCount = 0

        while guardCount < 6, let current = currentError {
            let line = "\(current.domain)#\(current.code): \(current.localizedDescription)"
            lines.append(line)

            if let reason = current.localizedFailureReason, !reason.isEmpty {
                lines.append("reason: \(reason)")
            }

            currentError = current.userInfo[NSUnderlyingErrorKey] as? NSError
            guardCount += 1
        }

        return lines.joined(separator: "\n")
    }
}

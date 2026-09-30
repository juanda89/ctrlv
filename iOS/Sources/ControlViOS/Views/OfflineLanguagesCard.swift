import ControlVCore
import SwiftUI
import Translation

/// The keyboard without Full Access (App Review 4.4.1): its V key translates
/// on the device with Apple's models, which need the two languages downloaded
/// once. This card shows whether they are and asks iOS to download them (the
/// system shows its own confirmation sheet).
@available(iOS 26.0, *)
struct OfflineLanguagesCard: View {
    let target: SupportedLanguage

    @State private var status: Status = .checking
    @State private var configuration: TranslationSession.Configuration?

    enum Status { case checking, ready, needsDownload, unsupported, failed }

    private var source: SupportedLanguage { OfflineLanguagePair.partner(of: target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: status == .ready ? "checkmark.circle.fill" : "iphone")
                    .font(.title3)
                    .foregroundStyle(status == .ready ? Color.green : Brand.blue)
                Text("Without Full Access").font(.body.weight(.semibold))
                Spacer(minLength: 0)
                if status == .ready {
                    Text("Ready").font(.caption2.weight(.bold)).foregroundStyle(.green)
                }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .needsDownload || status == .failed {
                Button(action: download) {
                    Label("Download \(source.rawValue) and \(target.rawValue)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(GlassButtonStyle())
                .accessibilityIdentifier("setup.downloadLanguages")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(20)
        .task(id: target) { await refresh() }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
            } catch {
                status = .failed
            }
            await refresh()
        }
    }

    private var detail: String {
        switch status {
        case .checking, .needsDownload:
            return "The keyboard still types, and its V key still translates, right on this device with Apple's translation models. Nothing leaves the device. Download the two languages once to use it."
        case .ready:
            return "The V key translates between \(source.rawValue) and \(target.rawValue) right on this device, even with Full Access off. Nothing leaves the device. Tones need Full Access."
        case .unsupported:
            return "This device can't translate \(source.rawValue) to \(target.rawValue) on the device. The keyboard still types; turn on Full Access to translate."
        case .failed:
            return "The languages didn't download. Check your connection and try again, or download them in Settings › Apps › Translate."
        }
    }

    private func download() {
        let pair = TranslationSession.Configuration(
            source: Locale.Language(identifier: source.bcp47),
            target: Locale.Language(identifier: target.bcp47)
        )
        if configuration == pair { configuration?.invalidate() } else { configuration = pair }
    }

    private func refresh() async {
        let availability = LanguageAvailability()
        let result = await availability.status(
            from: Locale.Language(identifier: source.bcp47),
            to: Locale.Language(identifier: target.bcp47)
        )
        switch result {
        case .installed: status = .ready
        case .supported: status = status == .failed ? .failed : .needsDownload
        case .unsupported: status = .unsupported
        @unknown default: status = .unsupported
        }
    }
}

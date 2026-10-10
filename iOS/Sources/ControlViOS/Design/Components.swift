import ControlVCore
import SwiftUI

/// "Auto-detect → English" with a language menu on the target side.
struct LanguagePairRow: View {
    @Binding var target: SupportedLanguage

    var body: some View {
        HStack(spacing: 10) {
            Label("Auto-detect", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassPill(interactive: false)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)

            Menu {
                ForEach(SupportedLanguage.allCases) { language in
                    Button {
                        target = language
                    } label: {
                        if language == target { Label(language.rawValue, systemImage: "checkmark") } else { Text(language.rawValue) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(target.rawValue).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .glassPill(interactive: false)
            }
            .menuOrder(.fixed)

            Spacer(minLength: 0)
        }
    }
}

struct ToneChipRow: View {
    @Binding var tone: Tone

    private func symbol(for tone: Tone) -> String {
        switch tone {
        case .original: return "person.wave.2"
        case .formal: return "briefcase"
        case .casual: return "bubble.left.and.bubble.right"
        case .concise: return "scissors"
        case .custom: return "wand.and.stars"
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Tone.allCases) { option in
                    Chip(title: option.rawValue, systemImage: symbol(for: option), isSelected: option == tone) {
                        tone = option
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Numbered step used by the keyboard setup and the paywall.
struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Brand.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 56
    var shadow = true
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Brand.gradient)
            Text("V")
                .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Brand.blue.opacity(shadow ? 0.35 : 0), radius: size * 0.28, y: size * 0.14)
    }
}

/// What a trial that ran out says outside the paywall
/// (`TranslationError.requiresSubscription`): what happened and the one way
/// forward. Never "Try again": only a subscription gets past it.
struct UpgradePrompt: Equatable {
    let title: String
    /// Asks to subscribe right here (the card has a Subscribe button).
    let detail: String
    /// For a surface that cannot open the app: says where to subscribe.
    let detailOpenApp: String
    /// One line for the keyboard's status band. Keyboards may open nothing
    /// but Settings (App Review 4.4.1), so it only says where to go.
    let short: String

    init(_ error: TranslationError) {
        switch error {
        case .trialQuotaExceeded:
            title = "You've used today's \(TrialTranslationService.dailyLimit) free translations"
            detail = "Subscribe to Control-V Pro to keep going, or come back tomorrow."
            detailOpenApp = "Open the Control-V app to subscribe, or come back tomorrow."
            short = "Daily free limit reached. Subscribe in the Control-V app."
        case .trialTextTooLong(let maxWords):
            title = "Too long for the free trial"
            detail = "The trial translates up to \(maxWords) words at a time. Subscribe to Control-V Pro for longer texts."
            detailOpenApp = "The trial translates up to \(maxWords) words at a time. Open the Control-V app to subscribe."
            short = "Too long for the trial. Subscribe in the Control-V app."
        default:
            title = "Your free trial has ended"
            detail = "Subscribe to Control-V Pro to keep translating in any app."
            detailOpenApp = "Open the Control-V app to subscribe and keep translating."
            short = "Free trial ended. Subscribe in the Control-V app."
        }
    }
}

/// The trial-ended card of the translation and share sheets. `subscribe` is
/// nil where the app cannot be opened; the card then says where to go.
struct UpgradeCard: View {
    let prompt: UpgradePrompt
    let subscribe: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.title).font(.subheadline.weight(.semibold))
                    Text(subscribe == nil ? prompt.detailOpenApp : prompt.detail)
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let subscribe {
                Button("Subscribe", action: subscribe)
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .accessibilityIdentifier("upgrade.subscribe")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }
}

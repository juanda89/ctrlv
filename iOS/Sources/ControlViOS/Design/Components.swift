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

import AppKit
import SwiftUI

enum MenuTheme {
    static let blue = Color(red: 0.16, green: 0.48, blue: 0.95)
    static let cyan = Color(red: 0.32, green: 0.80, blue: 0.90)

    static let groupFill = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.72),
        dark: NSColor.white.withAlphaComponent(0.09)
    )
    static let groupBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.11)
    )
    static let controlFill = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.56),
        dark: NSColor.white.withAlphaComponent(0.05)
    )
    static let controlBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.07),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let keycapFill = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.44),
        dark: NSColor.white.withAlphaComponent(0.05)
    )
    static let keycapBorder = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.11)
    )
    static let iconFill = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.90),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let shadowColor = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.05),
        dark: NSColor.black.withAlphaComponent(0.18)
    )
    static let divider = Color(nsColor: .separatorColor).opacity(0.55)
    static let subtleText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let selectedFill = blue.opacity(0.16)
    static let selectedBorder = blue.opacity(0.28)

    static func tintedSurface(_ tint: Color) -> Color {
        tint.opacity(0.12)
    }

    static func tintedBorder(_ tint: Color) -> Color {
        tint.opacity(0.22)
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return dark
                }
                return light
            }
        )
    }
}

struct NativeGroupCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MenuTheme.groupFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MenuTheme.groupBorder, lineWidth: 1)
        )
        .shadow(color: MenuTheme.shadowColor, radius: 12, x: 0, y: 4)
    }
}

struct MenuCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NativeGroupCard {
            content
        }
    }
}

struct NativeControlSurface<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 11
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 7

    init(
        cornerRadius: CGFloat = 11,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 7,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MenuTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MenuTheme.controlBorder, lineWidth: 1)
            )
    }
}

struct NativeSectionLabel: View {
    let systemName: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            IconBubble(systemName: systemName, tint: tint)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

struct NativeMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(MenuTheme.divider)
            .frame(height: 1)
    }
}

struct IconBubble: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(MenuTheme.iconFill)
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
    }
}

struct NativeKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(MenuTheme.subtleText)
            .frame(minWidth: 20)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MenuTheme.keycapFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MenuTheme.keycapBorder, lineWidth: 1)
            )
    }
}

struct ShortcutBadge: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                NativeKeycap(text: key)
            }
        }
    }
}

struct NativeAccessoryButton: View {
    let systemName: String
    var tint: Color = MenuTheme.subtleText
    var filled = false
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Color.white : tint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(filled ? tint : MenuTheme.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(filled ? tint.opacity(0.25) : MenuTheme.controlBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct BrandMarkView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MenuTheme.controlFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MenuTheme.controlBorder, lineWidth: 1)
                )

            Text("V")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MenuTheme.blue, MenuTheme.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 30, height: 30)
    }
}

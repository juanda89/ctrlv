import SwiftUI

/// Brand tokens shared with the Mac app and the landing page.
enum Brand {
    static let cyan = Color(red: 0.32, green: 0.80, blue: 0.90)
    static let blue = Color(red: 0.16, green: 0.48, blue: 0.95)
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.10)
    static let gradient = LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gradientSoft = LinearGradient(colors: [cyan.opacity(0.9), blue.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Soft "aurora" wash behind every screen: system background plus two faint
/// brand glows. Quiet enough for glass to read on top of it.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [Brand.cyan.opacity(scheme == .dark ? 0.30 : 0.22), .clear], center: .init(x: 0.1, y: 0.0), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Brand.blue.opacity(scheme == .dark ? 0.26 : 0.16), .clear], center: .init(x: 1.0, y: 0.15), startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on iOS 26, thin material below. Same shape either way.
    @ViewBuilder
    func glassCard(_ radius: CGFloat = 22, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    @ViewBuilder
    /// `interactive` glass handles touches itself: use it only where the
    /// ButtonStyle applies it (GlassButtonStyle); inside a Button or Menu
    /// label it swallows the tap and the control never fires.
    func glassPill(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

/// The one loud element per screen: gradient capsule, white label.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    /// Shorter capsule for tight spaces (keyboard panel).
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 11 : 15)
            .frame(maxWidth: .infinity)
            .background(Brand.gradient, in: Capsule())
            .shadow(color: Brand.blue.opacity(isEnabled ? 0.28 : 0), radius: 14, y: 8)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Quiet secondary action: glass pill.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassPill()
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Selectable pill used for tones and languages.
struct Chip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption.weight(.semibold)) }
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(Brand.gradient)
                }
            }
        }
        .buttonStyle(.plain)
        .glassPill(interactive: !isSelected)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Small transient confirmation ("Copied").
struct Toast: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassPill(interactive: false)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    func toast(_ text: String?, isPresented: Binding<Bool>) -> some View {
        overlay(alignment: .bottom) {
            if isPresented.wrappedValue, let text {
                Toast(text: text)
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation { isPresented.wrappedValue = false }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: isPresented.wrappedValue)
    }
}

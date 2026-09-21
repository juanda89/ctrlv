import SwiftUI
import UIKit

/// One character key, drawn and behaving like the system keyboard's:
/// - touch down shows the character preview above the key (and clicks),
/// - holding a letter with variants opens the accent strip; sliding picks one,
/// - touch up inserts.
///
/// A `Button` cannot do this: it commits on touch up only, with no way to
/// draw the preview on touch down or to track the finger across the strip.
struct KeyView: View {
    let label: String
    let alternatives: [String]
    let width: CGFloat
    let height: CGFloat
    let style: KeyStyle
    /// Where the key sits in its row, so the preview never leaves the screen.
    var edge: Edge = .none
    let onCommit: (String) -> Void

    enum Edge { case none, leading, trailing }

    @State private var pressed = false
    @State private var showsAlternatives = false
    @State private var selectedAlternative = 0
    @State private var holdTask: Task<Void, Never>?

    private var previewWidth: CGFloat { max(width * 1.6, 54) }
    /// Rises 34 pt above the key: what fits in the band above the top row.
    private let previewHeight: CGFloat = 46
    private let previewOverlap: CGFloat = 12
    private let alternativeWidth: CGFloat = 36

    var body: some View {
        Text(label)
            .font(.system(size: style.letterSize))
            .foregroundStyle(style.glyph)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: style.radius, style: .circular).fill(style.face))
            .overlay(alignment: .top) {
                if pressed { preview }
            }
            .zIndex(pressed ? 1 : 0)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged(handleChange)
                    .onEnded(handleEnd)
            )
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isKeyboardKey)
    }

    // MARK: - Preview and accent strip

    @ViewBuilder
    private var preview: some View {
        if showsAlternatives, !alternatives.isEmpty {
            alternativeStrip
        } else {
            singlePreview
        }
    }

    /// The enlarged character, sitting on the key like a balloon.
    private var singlePreview: some View {
        Text(label)
            .font(.system(size: style.previewSize))
            .foregroundStyle(style.glyph)
            .frame(width: previewWidth, height: previewHeight)
            .background(RoundedRectangle(cornerRadius: style.radius + 3, style: .circular).fill(style.popup))
            .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            .offset(x: previewShift, y: -previewHeight + previewOverlap)
    }

    private var previewShift: CGFloat {
        switch edge {
        case .none: return 0
        case .leading: return (previewWidth - width) / 2
        case .trailing: return -(previewWidth - width) / 2
        }
    }

    private var alternativeStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, alternative in
                Text(alternative)
                    .font(.system(size: style.letterSize + 2))
                    .foregroundStyle(index == selectedAlternative ? Color.white : style.glyph)
                    .frame(width: alternativeWidth, height: 40)
                    .background {
                        if index == selectedAlternative {
                            RoundedRectangle(cornerRadius: 6, style: .circular).fill(style.accent)
                        }
                    }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: style.radius + 3, style: .circular).fill(style.popup))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        .offset(x: stripShift, y: -previewHeight + previewOverlap)
    }

    private var stripWidth: CGFloat { CGFloat(alternatives.count) * alternativeWidth + 6 }

    /// The strip grows to the right from the key, or to the left near the
    /// trailing edge, like the system's.
    private var stripShift: CGFloat {
        edge == .trailing ? -(stripWidth - width) / 2 : (stripWidth - width) / 2
    }

    // MARK: - Touch handling

    private func handleChange(_ value: DragGesture.Value) {
        if !pressed {
            pressed = true
            selectedAlternative = 0
            UIDevice.current.playInputClick()
            guard !alternatives.isEmpty else { return }
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled, pressed else { return }
                showsAlternatives = true
            }
        }
        guard showsAlternatives else { return }
        // The finger's x relative to the strip's leading edge picks the item.
        let origin = edge == .trailing ? width - stripWidth + 3 : 3
        let index = Int(((value.location.x - origin) / alternativeWidth).rounded(.down))
        selectedAlternative = min(max(index, 0), alternatives.count - 1)
    }

    private func handleEnd(_ value: DragGesture.Value) {
        holdTask?.cancel()
        defer {
            pressed = false
            showsAlternatives = false
        }
        // A finger that wandered far off the key (but not into the strip) is a
        // cancelled tap, as on the system keyboard.
        let inside = value.location.y > -previewHeight && value.location.y < height + 20
            && value.location.x > -30 && value.location.x < width + 30
        if showsAlternatives {
            onCommit(alternatives[selectedAlternative])
        } else if inside {
            onCommit(label)
        }
    }
}

/// Colours and sizes measured on the iOS 26 keyboard: every key is the same
/// white (or the same grey in dark mode), corners are a circular 8 pt, letters
/// have a 17 pt cap height, and there is no shadow.
struct KeyStyle {
    let face: Color
    let pressedFace: Color
    let popup: Color
    let glyph: Color
    let accent: Color
    let radius: CGFloat = 8
    /// 22 pt renders the 17 pt cap height measured on the system keys.
    let letterSize: CGFloat = 22
    let previewSize: CGFloat = 36

    static func system(dark: Bool, accent: Color) -> KeyStyle {
        if dark {
            return KeyStyle(face: Color(red: 64/255, green: 64/255, blue: 65/255),
                            pressedFace: Color(red: 92/255, green: 92/255, blue: 94/255),
                            popup: Color(red: 92/255, green: 92/255, blue: 94/255),
                            glyph: .white, accent: accent)
        }
        return KeyStyle(face: .white,
                        pressedFace: Color(red: 213/255, green: 215/255, blue: 220/255),
                        popup: .white,
                        glyph: .black, accent: accent)
    }
}

/// Modifier keys (shift, delete, 123, space, return): no preview, the face
/// darkens while pressed, and the action fires on touch up inside the key.
/// `repeatWhileHeld` (delete) fires again every 90 ms after a short hold.
struct ModifierKeyView<Label: View>: View {
    let width: CGFloat
    let height: CGFloat
    let style: KeyStyle
    var repeatWhileHeld = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        label()
            .foregroundStyle(style.glyph)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: style.radius, style: .circular).fill(pressed ? style.pressedFace : style.face))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        UIDevice.current.playInputClick()
                        if repeatWhileHeld { startRepeating() }
                    }
                    .onEnded { value in
                        let fired = repeatTask != nil && repeatWhileHeld && repeatDidFire
                        repeatTask?.cancel(); repeatTask = nil; repeatDidFire = false
                        pressed = false
                        let inside = value.location.x > -20 && value.location.x < width + 20
                            && value.location.y > -20 && value.location.y < height + 20
                        if inside, !fired { action() }
                    }
            )
            .accessibilityAddTraits(.isKeyboardKey)
    }

    @State private var repeatDidFire = false

    private func startRepeating() {
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                repeatDidFire = true
                action()
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }
}

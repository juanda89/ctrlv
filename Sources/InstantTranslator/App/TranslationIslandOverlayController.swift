import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TranslationIslandOverlayController {
    private enum Metrics {
        static let expandedSize = NSSize(width: 176, height: 38)
        static let collapsedSize = NSSize(width: 132, height: 8)
        static let topInset: CGFloat = 5
        static let visibleDuration: TimeInterval = 0.56
        static let hideDuration: TimeInterval = 0.44
    }

    private var panel: NSPanel?
    private var isVisible = false

    func show() {
        ensurePanel()
        guard let panel else { return }

        if isVisible {
            repositionIfNeeded()
            return
        }

        repositionIfNeeded()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true

        let visibleFrame = frame(for: .visible)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.visibleDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            panel.animator().setFrame(visibleFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        guard panel.isVisible else {
            isVisible = false
            return
        }

        let hiddenFrame = frame(for: .hidden)
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let initialFrame = frame(for: .hidden)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: TranslationIslandOverlayView())
        hostingView.frame = NSRect(origin: .zero, size: initialFrame.size)
        hostingView.autoresizingMask = [.width, .height]

        let content = NSView(frame: NSRect(origin: .zero, size: initialFrame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        content.addSubview(hostingView)
        panel.contentView = content

        self.panel = panel
    }

    private func repositionIfNeeded() {
        guard let panel else { return }
        panel.setFrame(frame(for: isVisible ? .visible : .hidden), display: false)
    }

    private enum OverlayState {
        case hidden
        case visible
    }

    private func frame(for state: OverlayState) -> NSRect {
        let bounds = targetScreenBounds()
        let size = (state == .visible) ? Metrics.expandedSize : Metrics.collapsedSize
        let x = bounds.midX - (size.width / 2)

        switch state {
        case .visible:
            let y = bounds.maxY - size.height - Metrics.topInset
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        case .hidden:
            let y = bounds.maxY + 2
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
    }

    private func targetScreenBounds() -> NSRect {
        if let main = NSScreen.main?.visibleFrame {
            return main
        }

        if let underMouse = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.visibleFrame {
            return underMouse
        }

        return NSScreen.screens.first?.visibleFrame ?? .zero
    }
}

private struct TranslationIslandOverlayView: View {
    private let aqua = Color(red: 0.00, green: 0.95, blue: 0.99)
    private let blue = Color(red: 0.24, green: 0.56, blue: 0.99)

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(aqua.opacity(0.14))
                    .frame(width: 21, height: 21)
                Text("V")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [blue, aqua],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Spacer(minLength: 0)

            TranslationWaveView(accent: aqua)
        }
        .padding(.horizontal, 13)
        .frame(width: 176, height: 38)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(aqua.opacity(0.30), lineWidth: 0.9)
        )
        .shadow(color: aqua.opacity(0.24), radius: 9, x: 0, y: 4)
    }
}

private struct TranslationWaveView: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 3) {
                ForEach(0..<5) { index in
                    let scale = waveScale(elapsed: elapsed, index: index)
                    Capsule(style: .continuous)
                        .fill(accent)
                        .frame(width: 3, height: 14)
                        .scaleEffect(x: 1, y: scale, anchor: .center)
                        .shadow(color: accent.opacity(0.65), radius: 3, x: 0, y: 0)
                }
            }
        }
        .frame(height: 16)
    }

    private func waveScale(elapsed: TimeInterval, index: Int) -> CGFloat {
        let phase = elapsed * 7.4 + Double(index) * 0.75
        return 0.34 + CGFloat(abs(sin(phase))) * 0.86
    }
}

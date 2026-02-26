import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TranslationIslandOverlayController {
    private enum Metrics {
        static let expandedSize = NSSize(width: 224, height: 44)
        static let collapsedSize = NSSize(width: 158, height: 10)
        static let topInset: CGFloat = 1
        static let visibleDuration: TimeInterval = 0.36
        static let hideDuration: TimeInterval = 0.62
        static let minimumVisibleDuration: TimeInterval = 0.95
    }

    private var panel: NSPanel?
    private var isVisible = false
    private var shownAt: Date?
    private var scheduledHide: DispatchWorkItem?

    func show() {
        ensurePanel()
        guard let panel else { return }
        scheduledHide?.cancel()
        scheduledHide = nil

        if isVisible {
            repositionIfNeeded()
            return
        }

        repositionIfNeeded()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true
        shownAt = Date()

        let visibleFrame = frame(for: .visible)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.visibleDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
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

        if let shownAt {
            let elapsed = Date().timeIntervalSince(shownAt)
            if elapsed < Metrics.minimumVisibleDuration {
                let remaining = Metrics.minimumVisibleDuration - elapsed
                scheduledHide?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        self?.hideNow()
                    }
                }
                scheduledHide = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
                return
            }
        }

        hideNow()
    }

    private func hideNow() {
        guard let panel else { return }
        let hiddenFrame = frame(for: .hidden)
        scheduledHide?.cancel()
        scheduledHide = nil
        isVisible = false
        shownAt = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.hideDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.40, 0.0, 0.20, 1.0)
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
        panel.hasShadow = true
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
            let y = bounds.maxY + 4
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
    }

    private func targetScreenBounds() -> NSRect {
        if let underMouse = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.frame {
            return underMouse
        }

        if let main = NSScreen.main?.frame {
            return main
        }

        return NSScreen.screens.first?.frame ?? .zero
    }
}

private struct TranslationIslandOverlayView: View {
    private let aqua = Color(red: 0.00, green: 0.95, blue: 0.99)
    private let blue = Color(red: 0.24, green: 0.56, blue: 0.99)
    private let islandWidth: CGFloat = 224
    private let islandHeight: CGFloat = 44

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 15, bottomLeading: 23, bottomTrailing: 23, topTrailing: 15),
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(aqua.opacity(0.16))
                    .frame(width: 24, height: 24)
                Text("V")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [blue, aqua],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Spacer(minLength: 0)

            TranslationWaveView(accent: aqua.opacity(0.96))
        }
        .padding(.horizontal, 15)
        .frame(width: islandWidth, height: islandHeight)
        .background {
            islandShape
                .fill(.ultraThinMaterial)
                .overlay(islandShape.fill(Color.black.opacity(0.74)))
        }
        .overlay {
            islandShape
                .stroke(Color.white.opacity(0.11), lineWidth: 0.9)
        }
        .overlay(alignment: .top) {
            islandShape
                .inset(by: 0.6)
                .stroke(aqua.opacity(0.22), lineWidth: 0.7)
                .blur(radius: 0.25)
                .mask(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 9)
        .shadow(color: aqua.opacity(0.14), radius: 7, x: 0, y: 3)
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
                        .frame(width: 2.8, height: 15)
                        .scaleEffect(x: 1, y: scale, anchor: .center)
                        .shadow(color: accent.opacity(0.58), radius: 2.5, x: 0, y: 0)
                }
            }
        }
        .frame(height: 17)
    }

    private func waveScale(elapsed: TimeInterval, index: Int) -> CGFloat {
        let phase = elapsed * 5.35 + Double(index) * 0.68
        return 0.30 + CGFloat(abs(sin(phase))) * 0.92
    }
}

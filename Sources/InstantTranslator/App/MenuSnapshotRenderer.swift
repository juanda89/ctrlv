import AppKit
import Foundation

enum MenuSnapshotRendererError: LocalizedError {
    case missingContentView
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            "Could not access menu preview content view"
        case .bitmapCreationFailed:
            "Could not create bitmap for menu preview"
        case .pngEncodingFailed:
            "Could not encode menu preview snapshot as PNG"
        }
    }
}

@MainActor
enum MenuSnapshotRenderer {
    static func render(
        rootView: MenuBarView,
        appearance: MenuPreviewAppearance,
        outputURL: URL
    ) throws {
        let controller = NativePopoverHostingController(rootView: rootView)
        let anchorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 36),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        anchorWindow.backgroundColor = .clear
        anchorWindow.isOpaque = false
        anchorWindow.hasShadow = false
        anchorWindow.level = .floating
        anchorWindow.alphaValue = 0.01
        anchorWindow.center()

        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        anchorWindow.contentView = anchorView
        anchorWindow.makeKeyAndOrderFront(nil)

        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 336, height: 560)
        popover.contentViewController = controller

        if let nsAppearance = appearance.nsAppearance {
            anchorWindow.appearance = nsAppearance
            controller.view.appearance = nsAppearance
        }

        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)

        guard let contentView = popover.contentViewController?.view else {
            popover.performClose(nil)
            anchorWindow.close()
            throw MenuSnapshotRendererError.missingContentView
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        contentView.frame = NSRect(origin: .zero, size: popover.contentSize)
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        let bounds = contentView.bounds
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            popover.performClose(nil)
            anchorWindow.close()
            throw MenuSnapshotRendererError.bitmapCreationFailed
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            popover.performClose(nil)
            anchorWindow.close()
            throw MenuSnapshotRendererError.pngEncodingFailed
        }

        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try pngData.write(to: outputURL)

        popover.performClose(nil)
        anchorWindow.orderOut(nil)
        anchorWindow.close()
    }
}

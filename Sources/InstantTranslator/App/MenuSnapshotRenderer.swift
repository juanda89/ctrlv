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
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.setContentSize(NSSize(width: 336, height: 560))
        window.appearance = appearance.nsAppearance

        guard let contentView = window.contentView else {
            throw MenuSnapshotRendererError.missingContentView
        }

        contentView.frame = NSRect(origin: .zero, size: NSSize(width: 336, height: 560))
        contentView.layoutSubtreeIfNeeded()
        window.display()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        let bounds = contentView.bounds
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw MenuSnapshotRendererError.bitmapCreationFailed
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw MenuSnapshotRendererError.pngEncodingFailed
        }

        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try pngData.write(to: outputURL)
    }
}

import AppKit
import SwiftUI

@MainActor
final class NativePopoverHostingController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>
    private let materialView = NSVisualEffectView()

    init(rootView: Content) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        view = container

        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .popover
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.masksToBounds = true
        materialView.layer?.cornerRadius = 18

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        container.addSubview(materialView)
        materialView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: container.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            hostingController.view.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: materialView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])

        updateBorderColor()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateBorderColor()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateBorderColor()
    }

    private func updateBorderColor() {
        materialView.layer?.borderWidth = 1
        materialView.layer?.borderColor = borderColor.cgColor
    }

    private var borderColor: NSColor {
        if view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.14)
        }
        return NSColor.black.withAlphaComponent(0.06)
    }
}

import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    init(contentView: AnyView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        hostingController.view.autoresizingMask = [.width, .height]
        contentViewController = hostingController
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

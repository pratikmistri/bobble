import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainPanel: FloatingPanel!
    private let manager = ChatHeadsManager()
    private let positionManager = WindowPositionManager()
    private var statusItem: NSStatusItem?
    private var isCollapsingSession = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        setupMainPanel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cleanup),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "Bobble")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Bobble", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupMainPanel() {
        let rootView = BobbleRootView(
            manager: manager,
            onHeadTapped: { [weak self] session in
                self?.toggleSession(session)
            },
            onClose: { [weak self] in
                self?.collapseSession()
            },
            onAddSession: { [weak self] in
                self?.manager.addSession()
            }
        )

        let size = positionManager.collapsedPanelSize(count: 0)
        mainPanel = FloatingPanel(
            contentView: AnyView(rootView),
            size: size
        )
        mainPanel.delegate = self

        let origin = positionManager.panelOrigin(for: size)
        mainPanel.setFrameOrigin(origin)
        mainPanel.orderFrontRegardless()

        // Deferred so it doesn't race with expandSession
        manager.onSessionsChanged = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePanelSize()
            }
        }

        manager.onSessionAdded = { [weak self] session in
            self?.expandSession(session)
        }
    }

    // MARK: - Session toggling

    private func toggleSession(_ session: ChatSession) {
        if manager.expandedSessionId == session.id {
            collapseSession()
        } else if manager.expandedSessionId != nil {
            // Already expanded — switch to different session (no panel resize needed)
            withAnimation(DesignTokens.motionLayout) {
                manager.expandedSessionId = session.id
            }
        } else {
            expandSession(session)
        }
    }

    private func expandSession(_ session: ChatSession) {
        // Pre-size the panel so the head->window morph has enough room immediately.
        let size = positionManager.expandedPanelSize(headsCount: manager.sessions.count)
        let origin = positionManager.panelOrigin(for: size)

        // Resize panel synchronously
        mainPanel.setFrame(NSRect(origin: origin, size: size), display: true)

        // Set state in the same synchronous block — SwiftUI won't re-render
        // until the run loop cycles, by which point the frame is already correct.
        withAnimation(DesignTokens.motionLayout) {
            manager.expandedSessionId = session.id
        }
    }

    private func collapseSession() {
        guard manager.expandedSessionId != nil, !isCollapsingSession else { return }
        isCollapsingSession = true

        let size = positionManager.collapsedPanelSize(count: max(manager.sessions.count, 1))

        // Collapse content and panel frame on the same motion curve for a connected transition.
        withAnimation(DesignTokens.motionLayout) {
            manager.expandedSessionId = nil
        }
        animatePanelFrame(to: size, duration: 0.34) { [weak self] in
            self?.isCollapsingSession = false
        }
    }

    // MARK: - Panel sizing

    private func updatePanelSize() {
        let count = max(manager.sessions.count, 1)
        let size: NSSize
        if manager.expandedSessionId != nil {
            size = positionManager.expandedPanelSize(headsCount: count)
        } else {
            size = positionManager.collapsedPanelSize(count: count)
        }
        animatePanelFrame(to: size, duration: 0.35)
    }

    private func animatePanelFrame(to size: NSSize, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let origin = positionManager.panelOrigin(for: size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            mainPanel.animator().setFrame(
                NSRect(origin: origin, size: size),
                display: true
            )
        } completionHandler: {
            completion?()
        }
    }

    @objc private func cleanup() {
        manager.terminateAll()
    }

    @objc private func quitApp() {
        cleanup()
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainPanel else { return true }

        // Defer collapse to avoid mutating layout during AppKit close handling.
        DispatchQueue.main.async { [weak self] in
            self?.collapseSession()
        }
        return false
    }
}

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainPanel: FloatingPanel!
    private let manager = ChatHeadsManager()
    private let positionManager = WindowPositionManager()
    private var statusItem: NSStatusItem?
    private var isCollapsingSession = false
    private var panelAnchor: NSPoint = .zero
    private var lastDragMouseLocation: NSPoint?
    private var lastDragSample: (origin: NSPoint, time: TimeInterval)?
    private var tossVelocity = CGVector.zero
    private var physicsTimer: Timer?
    private var lastPhysicsStepTime: TimeInterval?

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
            },
            onHeadsDragChanged: { [weak self] in
                self?.movePanelWithMouse()
            },
            onHeadsDragEnded: { [weak self] in
                self?.finishMovingPanel()
            }
        )

        let size = positionManager.collapsedPanelSize(count: 0)
        mainPanel = FloatingPanel(
            contentView: AnyView(rootView),
            size: size
        )
        mainPanel.delegate = self

        panelAnchor = positionManager.defaultPanelAnchor()
        let origin = positionManager.panelOrigin(for: size, anchor: panelAnchor)
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
        stopPhysics()

        // Pre-size the panel so the head->window morph has enough room immediately.
        let size = positionManager.expandedPanelSize(headsCount: manager.sessions.count)
        panelAnchor = positionManager.constrainedPanelAnchor(panelAnchor, for: size)
        let origin = positionManager.panelOrigin(for: size, anchor: panelAnchor)

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
        stopPhysics()
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
        stopPhysics()
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
        panelAnchor = positionManager.constrainedPanelAnchor(panelAnchor, for: size)
        let origin = positionManager.panelOrigin(for: size, anchor: panelAnchor)
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

    private func movePanelWithMouse() {
        let now = ProcessInfo.processInfo.systemUptime
        let mouseLocation = NSEvent.mouseLocation

        if lastDragMouseLocation == nil {
            stopPhysics()
            lastDragMouseLocation = mouseLocation
            lastDragSample = (origin: mainPanel.frame.origin, time: now)
            tossVelocity = .zero
            return
        }

        guard let lastDragMouseLocation else { return }

        let proposedOrigin = NSPoint(
            x: mainPanel.frame.origin.x + (mouseLocation.x - lastDragMouseLocation.x),
            y: mainPanel.frame.origin.y + (mouseLocation.y - lastDragMouseLocation.y)
        )
        let size = mainPanel.frame.size
        let resolvedOrigin = positionManager.constrainedPanelOrigin(proposedOrigin, for: size)

        mainPanel.setFrameOrigin(resolvedOrigin)
        panelAnchor = positionManager.panelAnchor(for: resolvedOrigin, size: size)
        self.lastDragMouseLocation = mouseLocation

        if let lastDragSample {
            let dt = CGFloat(max(now - lastDragSample.time, 1.0 / 240.0))
            let rawVelocity = CGVector(
                dx: (resolvedOrigin.x - lastDragSample.origin.x) / dt,
                dy: (resolvedOrigin.y - lastDragSample.origin.y) / dt
            )
            tossVelocity = CGVector(
                dx: (tossVelocity.dx * 0.25) + (rawVelocity.dx * 0.75),
                dy: (tossVelocity.dy * 0.25) + (rawVelocity.dy * 0.75)
            )
        }

        lastDragSample = (origin: resolvedOrigin, time: now)
    }

    private func finishMovingPanel() {
        lastDragMouseLocation = nil
        lastDragSample = nil
        startPhysicsIfNeeded()
    }

    private func startPhysicsIfNeeded() {
        tossVelocity = clampedVelocity(tossVelocity)

        guard hypot(tossVelocity.dx, tossVelocity.dy) > 90 else {
            tossVelocity = .zero
            return
        }

        stopPhysics()
        lastPhysicsStepTime = ProcessInfo.processInfo.systemUptime

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.stepPhysics()
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        physicsTimer = timer
    }

    private func stepPhysics() {
        guard physicsTimer != nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = CGFloat(min(max(now - (lastPhysicsStepTime ?? now), 1.0 / 240.0), 1.0 / 30.0))
        lastPhysicsStepTime = now

        var velocity = tossVelocity
        var origin = mainPanel.frame.origin
        let size = mainPanel.frame.size

        origin.x += velocity.dx * dt
        origin.y += velocity.dy * dt

        let constrainedOrigin = positionManager.constrainedPanelOrigin(origin, for: size)

        if constrainedOrigin.x != origin.x {
            origin.x = constrainedOrigin.x
            velocity.dx = 0
        }

        if constrainedOrigin.y != origin.y {
            origin.y = constrainedOrigin.y
            velocity.dy = 0
        }

        let drag = CGFloat(exp(-3.2 * Double(dt)))
        velocity.dx *= drag
        velocity.dy *= drag

        mainPanel.setFrameOrigin(origin)
        panelAnchor = positionManager.panelAnchor(for: origin, size: size)
        tossVelocity = velocity

        if hypot(velocity.dx, velocity.dy) < 18 {
            stopPhysics()
        }
    }

    private func stopPhysics() {
        physicsTimer?.invalidate()
        physicsTimer = nil
        lastPhysicsStepTime = nil
    }

    private func clampedVelocity(_ velocity: CGVector) -> CGVector {
        let speed = hypot(velocity.dx, velocity.dy)
        let maxSpeed: CGFloat = 2600

        guard speed > maxSpeed, speed > 0 else { return velocity }

        let scale = maxSpeed / speed
        return CGVector(
            dx: velocity.dx * scale,
            dy: velocity.dy * scale
        )
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

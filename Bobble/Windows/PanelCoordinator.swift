import AppKit
import SwiftUI

final class PanelCoordinator: NSObject, NSWindowDelegate {
    enum AnimationMode: Equatable {
        case fullFrame
        case verticalCollapse
    }

    var isCollapsingSession = false
    var suppressNextPanelSizeUpdate = false
    var onDockSideChange: ((PanelDockSide) -> Void)?
    var onWindowCloseRequested: (() -> Void)?

    var dockSide: PanelDockSide = .trailing {
        didSet {
            guard oldValue != dockSide else { return }
            onDockSideChange?(dockSide)
        }
    }

    private let positionManager: WindowPositionManager
    private var mainPanel: FloatingPanel!
    private var panelAnchor: NSPoint = .zero
    private var preferredPanelAnchor: NSPoint = .zero
    private var lastDragMouseLocation: NSPoint?
    private var lastDragSample: (origin: NSPoint, time: TimeInterval)?
    private var tossVelocity = CGVector.zero
    private var physicsTimer: Timer?
    private var lastPhysicsStepTime: TimeInterval?

    init(positionManager: WindowPositionManager = WindowPositionManager()) {
        self.positionManager = positionManager
        super.init()
    }

    func install(rootView: AnyView, layoutMode: ChatHeadsLayoutMode) {
        let size = positionManager.collapsedPanelSize(count: 0, layoutMode: layoutMode)
        mainPanel = FloatingPanel(
            contentView: rootView,
            size: size
        )
        mainPanel.delegate = self

        panelAnchor = positionManager.defaultPanelAnchor()
        preferredPanelAnchor = panelAnchor
        dockSide = .trailing
        let origin = positionManager.panelOrigin(for: size, anchor: panelAnchor, dockSide: dockSide)
        mainPanel.setFrameOrigin(origin)
        mainPanel.orderFrontRegardless()
    }

    func collapsedPanelSize(count: Int, layoutMode: ChatHeadsLayoutMode) -> NSSize {
        positionManager.collapsedPanelSize(count: count, layoutMode: layoutMode)
    }

    func handleSessionsChanged(sessionCount: Int, expandedIndex: Int?, layoutMode: ChatHeadsLayoutMode) {
        if suppressNextPanelSizeUpdate {
            suppressNextPanelSizeUpdate = false
            return
        }
        updatePanelSize(sessionCount: sessionCount, expandedIndex: expandedIndex, layoutMode: layoutMode)
    }

    func expand(
        sessionCount: Int,
        expandedIndex: Int?,
        layoutMode: ChatHeadsLayoutMode,
        animateStateChange: Bool = true,
        stateChange: @escaping () -> Void
    ) {
        stopPhysics()

        let size = positionManager.expandedPanelSize(
            headsCount: sessionCount,
            expandedIndex: expandedIndex,
            layoutMode: layoutMode
        )
        let finalState = resolvedPanelState(for: size, selectingBestDockSide: true)
        panelAnchor = finalState.anchor
        dockSide = finalState.dockSide
        performPanelLayoutMutation {
            self.mainPanel.setFrame(finalState.frame, display: true)

            if animateStateChange {
                withAnimation(DesignTokens.motionLayout) {
                    stateChange()
                }
            } else {
                stateChange()
            }
        }
    }

    func collapse(
        sessionCount: Int,
        layoutMode: ChatHeadsLayoutMode,
        stateChange: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        stopPhysics()
        isCollapsingSession = true

        let size = positionManager.collapsedPanelSize(count: max(sessionCount, 1), layoutMode: layoutMode)
        withAnimation(DesignTokens.motionLayout) {
            stateChange()
        }
        animatePanelFrame(to: size, duration: 0.34, mode: .verticalCollapse) { [weak self] in
            guard let self else { return }
            self.isCollapsingSession = false
            completion?()
        }
    }

    func focusExpandedSession(
        sessionCount: Int,
        expandedIndex: Int?,
        layoutMode: ChatHeadsLayoutMode,
        stateChange: @escaping () -> Void
    ) {
        let size = positionManager.expandedPanelSize(
            headsCount: max(sessionCount, 1),
            expandedIndex: expandedIndex,
            layoutMode: layoutMode
        )
        let finalState = resolvedPanelState(for: size, selectingBestDockSide: true)
        panelAnchor = finalState.anchor
        dockSide = finalState.dockSide
        performPanelLayoutMutation {
            self.mainPanel.setFrame(finalState.frame, display: true)

            withAnimation(DesignTokens.motionLayout) {
                stateChange()
            }
        }
    }

    func updatePanelSize(sessionCount: Int, expandedIndex: Int?, layoutMode: ChatHeadsLayoutMode) {
        stopPhysics()
        let size: NSSize
        if expandedIndex != nil {
            size = positionManager.expandedPanelSize(
                headsCount: max(sessionCount, 1),
                expandedIndex: expandedIndex,
                layoutMode: layoutMode
            )
        } else {
            size = positionManager.collapsedPanelSize(count: sessionCount, layoutMode: layoutMode)
        }
        animatePanelFrame(to: size, duration: 0.35)
    }

    func animatePanelFrame(
        to size: NSSize,
        duration: TimeInterval,
        mode: AnimationMode = .fullFrame,
        completion: (() -> Void)? = nil
    ) {
        let animatedFrame: NSRect
        let finalFrame: NSRect
        let finalDockSide: PanelDockSide
        let finalAnchor: NSPoint

        switch mode {
        case .fullFrame:
            let finalState = resolvedPanelState(for: size)
            finalFrame = finalState.frame
            finalDockSide = finalState.dockSide
            finalAnchor = finalState.anchor

            panelAnchor = finalAnchor
            dockSide = finalDockSide
            animatedFrame = finalFrame

        case .verticalCollapse:
            let finalState = resolvedPanelState(for: size)
            finalFrame = finalState.frame
            finalDockSide = finalState.dockSide
            finalAnchor = finalState.anchor
            animatedFrame = finalFrame
        }

        performPanelLayoutMutation {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                self.mainPanel.animator().setFrame(
                    animatedFrame,
                    display: true
                )
            } completionHandler: {
                self.panelAnchor = finalAnchor
                self.dockSide = finalDockSide
                self.performPanelLayoutMutation {
                    self.mainPanel.setFrame(finalFrame, display: true)
                    completion?()
                }
            }
        }
    }

    func applyCollapsedFrame(sessionCount: Int, layoutMode: ChatHeadsLayoutMode) {
        let finalSize = positionManager.collapsedPanelSize(count: sessionCount, layoutMode: layoutMode)
        panelAnchor = positionManager.constrainedPanelAnchor(
            preferredPanelAnchor,
            for: finalSize,
            dockSide: dockSide
        )
        let finalOrigin = positionManager.panelOrigin(
            for: finalSize,
            anchor: panelAnchor,
            dockSide: dockSide
        )
        performPanelLayoutMutation {
            self.mainPanel.setFrame(NSRect(origin: finalOrigin, size: finalSize), display: true)
        }
    }

    func movePanelWithMouse() {
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
        let resolvedOrigin = positionManager.constrainedPanelOrigin(
            proposedOrigin,
            for: size,
            dockSide: dockSide
        )

        mainPanel.setFrameOrigin(resolvedOrigin)
        panelAnchor = positionManager.panelAnchor(for: resolvedOrigin, size: size, dockSide: dockSide)
        preferredPanelAnchor = panelAnchor
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

    func finishMovingPanel() {
        lastDragMouseLocation = nil
        lastDragSample = nil
        panelAnchor = positionManager.panelAnchor(
            for: mainPanel.frame.origin,
            size: mainPanel.frame.size,
            dockSide: dockSide
        )
        preferredPanelAnchor = panelAnchor
        startPhysicsIfNeeded()
    }

    func stopPhysics() {
        physicsTimer?.invalidate()
        physicsTimer = nil
        lastPhysicsStepTime = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainPanel else { return true }

        DispatchQueue.main.async { [weak self] in
            self?.onWindowCloseRequested?()
        }
        return false
    }

    private func performPanelLayoutMutation(_ mutation: @escaping () -> Void) {
        DispatchQueue.main.async(execute: mutation)
    }

    private func resolvedPanelState(
        for size: NSSize,
        selectingBestDockSide: Bool = false
    ) -> (frame: NSRect, anchor: NSPoint, dockSide: PanelDockSide) {
        let clampedSize = positionManager.clampedPanelSize(size, anchor: preferredPanelAnchor)
        let resolvedDockSide = selectingBestDockSide
            ? bestDockSide(for: clampedSize, preferred: dockSide)
            : dockSide
        let anchor = positionManager.constrainedPanelAnchor(preferredPanelAnchor, for: clampedSize, dockSide: resolvedDockSide)
        let origin = positionManager.panelOrigin(for: clampedSize, anchor: anchor, dockSide: resolvedDockSide)
        return (
            frame: NSRect(origin: origin, size: clampedSize),
            anchor: anchor,
            dockSide: resolvedDockSide
        )
    }

    private func bestDockSide(for size: NSSize, preferred: PanelDockSide) -> PanelDockSide {
        let alternate: PanelDockSide = preferred == .leading ? .trailing : .leading
        let preferredShift = anchorShift(for: size, dockSide: preferred)
        let alternateShift = anchorShift(for: size, dockSide: alternate)

        if preferredShift <= 0.5 {
            return preferred
        }

        if alternateShift + 0.5 < preferredShift {
            return alternate
        }

        return preferred
    }

    private func anchorShift(for size: NSSize, dockSide: PanelDockSide) -> CGFloat {
        let resolvedAnchor = positionManager.constrainedPanelAnchor(preferredPanelAnchor, for: size, dockSide: dockSide)
        return abs(resolvedAnchor.x - preferredPanelAnchor.x)
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

        let constrainedOrigin = positionManager.constrainedPanelOrigin(origin, for: size, dockSide: dockSide)

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
        panelAnchor = positionManager.panelAnchor(for: origin, size: size, dockSide: dockSide)
        preferredPanelAnchor = panelAnchor
        tossVelocity = velocity

        if hypot(velocity.dx, velocity.dy) < 18 {
            stopPhysics()
        }
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
}

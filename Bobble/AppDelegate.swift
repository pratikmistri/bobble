import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PanelAnimationMode: Equatable {
        case fullFrame
        case verticalCollapse
    }

    private var mainPanel: FloatingPanel!
    private let manager = ChatHeadsManager()
    private let positionManager = WindowPositionManager()
    private let usageMonitor = UsageMonitor()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var providerMenuItems: [CLIBackend: NSMenuItem] = [:]
    private var usageMenuItems: [CLIBackend: UsageMenuItemGroup] = [:]
    private var refreshUsageMenuItem: NSMenuItem?
    private var isRefreshingUsage = false
    private var isCollapsingSession = false
    private var panelAnchor: NSPoint = .zero
    private var preferredPanelAnchor: NSPoint = .zero
    private var lastDragMouseLocation: NSPoint?
    private var lastDragSample: (origin: NSPoint, time: TimeInterval)?
    private var tossVelocity = CGVector.zero
    private var physicsTimer: Timer?
    private var lastPhysicsStepTime: TimeInterval?
    private var suppressNextPanelSizeUpdate = false
    private var lastAddSessionTimestamp: TimeInterval = 0
    private let addSessionThrottleInterval: TimeInterval = 0.2

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
            button.toolTip = "Bobble"
        }
        let menu = makeStatusMenu()
        statusMenu = menu
        statusItem?.menu = menu
        manager.onSelectedProviderChanged = { [weak self] provider in
            DispatchQueue.main.async {
                self?.updateProviderMenuSelection(provider)
            }
        }
        refreshUsage()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let providerRoot = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
        let providerSubmenu = NSMenu()
        providerMenuItems.removeAll()

        for provider in CLIBackend.allCases {
            let item = NSMenuItem(
                title: provider.displayName,
                action: #selector(selectProvider(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.rawValue
            providerMenuItems[provider] = item
            providerSubmenu.addItem(item)
        }

        providerRoot.submenu = providerSubmenu
        menu.addItem(providerRoot)
        menu.addItem(.separator())

        let usageHeader = NSMenuItem(title: "Usage", action: nil, keyEquivalent: "")
        usageHeader.isEnabled = false
        menu.addItem(usageHeader)
        usageMenuItems.removeAll()

        for provider in CLIBackend.allCases {
            let item = NSMenuItem()
            item.isEnabled = false

            let rowView = UsageMenuRowView()
            rowView.apply(.loading(for: provider))
            item.view = rowView

            usageMenuItems[provider] = UsageMenuItemGroup(item: item, rowView: rowView)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let refreshUsageItem = NSMenuItem(title: "Refresh Usage", action: #selector(refreshUsageMenuAction(_:)), keyEquivalent: "")
        refreshUsageItem.target = self
        refreshUsageMenuItem = refreshUsageItem
        menu.addItem(refreshUsageItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Bobble", action: #selector(quitApp), keyEquivalent: "q"))

        updateProviderMenuSelection(manager.selectedProvider)
        return menu
    }

    private func updateProviderMenuSelection(_ provider: CLIBackend) {
        for (candidate, item) in providerMenuItems {
            item.state = candidate == provider ? .on : .off
        }

        statusItem?.button?.toolTip = "Bobble (\(provider.displayName))"
    }

    private func refreshUsage(force: Bool = false) {
        guard !isRefreshingUsage else { return }

        isRefreshingUsage = true
        refreshUsageMenuItem?.title = "Refreshing Usage..."
        refreshUsageMenuItem?.isEnabled = false

        usageMonitor.refresh(force: force) { [weak self] summaries in
            guard let self else { return }

            for provider in CLIBackend.allCases {
                guard let group = self.usageMenuItems[provider] else { continue }
                let summary = summaries[provider] ?? ProviderUsageSummary.unavailable(
                    for: provider,
                    caption: "No local usage source found."
                )
                group.rowView.apply(summary)
            }

            self.refreshUsageMenuItem?.title = "Refresh Usage"
            self.refreshUsageMenuItem?.isEnabled = true
            self.isRefreshingUsage = false
        }
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
            onArchiveSession: { [weak self] session in
                self?.archiveSession(session)
            },
            onOpenHistorySession: { [weak self] session in
                self?.openHistorySession(session)
            },
            onDeleteHistorySession: { [weak self] session in
                self?.manager.deleteHistorySession(session)
            },
            onAddSession: { [weak self] in
                self?.handleAddSessionRequest()
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
        preferredPanelAnchor = panelAnchor
        manager.panelDockSide = .trailing
        let origin = positionManager.panelOrigin(for: size, anchor: panelAnchor, dockSide: manager.panelDockSide)
        mainPanel.setFrameOrigin(origin)
        mainPanel.orderFrontRegardless()

        // Deferred so it doesn't race with expandSession
        manager.onSessionsChanged = { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleSessionsChanged()
            }
        }

        manager.onSessionAdded = { [weak self] session in
            self?.suppressNextPanelSizeUpdate = true
            self?.expandSession(session, animateStateChange: false)
        }
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let provider = CLIBackend(rawValue: rawValue) else {
            return
        }

        manager.updateSelectedProvider(provider)
    }

    @objc private func refreshUsageMenuAction(_ sender: Any?) {
        refreshUsage(force: true)
    }

    // MARK: - Session toggling

    private func toggleSession(_ session: ChatSession) {
        if manager.expandedSessionId == session.id {
            collapseSession()
        } else if manager.expandedSessionId != nil {
            // Already expanded — resize for target index, then switch.
            focusExpandedSession(session)
        } else {
            expandSession(session)
        }
    }

    private func expandSession(_ session: ChatSession, animateStateChange: Bool = true) {
        stopPhysics()

        let expandedIndex = manager.sessions.firstIndex(where: { $0.id == session.id })
        let size = positionManager.expandedPanelSize(
            headsCount: manager.sessions.count,
            expandedIndex: expandedIndex
        )
        let finalState = resolvedPanelState(for: size, selectingBestDockSide: true)
        panelAnchor = finalState.anchor
        manager.panelDockSide = finalState.dockSide
        performPanelLayoutMutation {
            self.mainPanel.setFrame(finalState.frame, display: true)

            // Keep the SwiftUI state flip paired with the panel resize, but
            // defer both until the hosting view has finished its current layout pass.
            if animateStateChange {
                withAnimation(DesignTokens.motionLayout) {
                    self.manager.expandedSessionId = session.id
                }
            } else {
                self.manager.expandedSessionId = session.id
            }
        }
    }

    private func collapseSession() {
        guard manager.expandedSessionId != nil, !isCollapsingSession else { return }
        stopPhysics()
        isCollapsingSession = true

        let size = positionManager.collapsedPanelSize(count: max(manager.sessions.count, 1))
        withAnimation(DesignTokens.motionLayout) {
            manager.expandedSessionId = nil
        }
        animatePanelFrame(to: size, duration: 0.34, mode: .verticalCollapse) { [weak self] in
            guard let self else { return }
            self.isCollapsingSession = false
        }
    }

    // MARK: - Panel sizing

    private func handleSessionsChanged() {
        if suppressNextPanelSizeUpdate {
            suppressNextPanelSizeUpdate = false
            return
        }
        updatePanelSize()
    }

    private func archiveSession(_ session: ChatSession) {
        guard manager.expandedSessionId == session.id else {
            withAnimation(DesignTokens.motionFade) {
                manager.archiveSession(session)
            }
            return
        }

        guard !isCollapsingSession else { return }
        stopPhysics()
        isCollapsingSession = true

        let remainingCount = max(manager.sessions.count - 1, 0)
        let size = positionManager.collapsedPanelSize(count: remainingCount)

        withAnimation(DesignTokens.motionLayout) {
            manager.deletingSessionId = session.id
        }

        animatePanelFrame(to: size, duration: 0.22, mode: .verticalCollapse) { [weak self] in
            guard let self else { return }

            self.suppressNextPanelSizeUpdate = true
            self.manager.archiveSession(session)

            let finalSize = self.positionManager.collapsedPanelSize(count: self.manager.sessions.count)
            self.panelAnchor = self.positionManager.constrainedPanelAnchor(
                self.preferredPanelAnchor,
                for: finalSize,
                dockSide: self.manager.panelDockSide
            )
            let finalOrigin = self.positionManager.panelOrigin(
                for: finalSize,
                anchor: self.panelAnchor,
                dockSide: self.manager.panelDockSide
            )
            self.performPanelLayoutMutation {
                self.mainPanel.setFrame(NSRect(origin: finalOrigin, size: finalSize), display: true)
                self.isCollapsingSession = false
            }
        }
    }

    private func openHistorySession(_ session: ChatSession) {
        stopPhysics()
        if let activeSession = manager.sessions.first(where: { $0.id == session.id }) {
            if manager.expandedSessionId == activeSession.id {
                return
            }

            if manager.expandedSessionId != nil {
                focusExpandedSession(activeSession)
            } else {
                expandSession(activeSession)
            }
            return
        }

        _ = manager.restoreSessionFromHistory(session)
    }

    private func focusExpandedSession(_ session: ChatSession) {
        let expandedIndex = manager.sessions.firstIndex(where: { $0.id == session.id })
        let size = positionManager.expandedPanelSize(
            headsCount: max(manager.sessions.count, 1),
            expandedIndex: expandedIndex
        )
        let finalState = resolvedPanelState(for: size, selectingBestDockSide: true)
        panelAnchor = finalState.anchor
        manager.panelDockSide = finalState.dockSide
        performPanelLayoutMutation {
            self.mainPanel.setFrame(finalState.frame, display: true)

            withAnimation(DesignTokens.motionLayout) {
                self.manager.expandedSessionId = session.id
            }
        }
    }

    private func updatePanelSize() {
        stopPhysics()
        let size: NSSize
        if manager.expandedSessionId != nil {
            let expandedIndex = manager.expandedSessionId.flatMap { id in
                manager.sessions.firstIndex(where: { $0.id == id })
            }
            size = positionManager.expandedPanelSize(
                headsCount: max(manager.sessions.count, 1),
                expandedIndex: expandedIndex
            )
        } else {
            size = positionManager.collapsedPanelSize(count: manager.sessions.count)
        }
        animatePanelFrame(to: size, duration: 0.35)
    }

    private func animatePanelFrame(
        to size: NSSize,
        duration: TimeInterval,
        mode: PanelAnimationMode = .fullFrame,
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
            manager.panelDockSide = finalDockSide
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
                self.manager.panelDockSide = finalDockSide
                self.performPanelLayoutMutation {
                    self.mainPanel.setFrame(finalFrame, display: true)
                    completion?()
                }
            }
        }
    }

    private func performPanelLayoutMutation(_ mutation: @escaping () -> Void) {
        DispatchQueue.main.async(execute: mutation)
    }

    private func handleAddSessionRequest() {
        guard !isCollapsingSession else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAddSessionTimestamp >= addSessionThrottleInterval else { return }
        lastAddSessionTimestamp = now
        manager.addSession()
    }

    private func resolvedPanelState(
        for size: NSSize,
        selectingBestDockSide: Bool = false
    ) -> (frame: NSRect, anchor: NSPoint, dockSide: PanelDockSide) {
        let clampedSize = positionManager.clampedPanelSize(size, anchor: preferredPanelAnchor)
        let dockSide = selectingBestDockSide
            ? bestDockSide(for: clampedSize, preferred: manager.panelDockSide)
            : manager.panelDockSide
        let anchor = positionManager.constrainedPanelAnchor(preferredPanelAnchor, for: clampedSize, dockSide: dockSide)
        let origin = positionManager.panelOrigin(for: clampedSize, anchor: anchor, dockSide: dockSide)
        return (
            frame: NSRect(origin: origin, size: clampedSize),
            anchor: anchor,
            dockSide: dockSide
        )
    }

    private func bestDockSide(for size: NSSize, preferred: PanelDockSide) -> PanelDockSide {
        let alternate: PanelDockSide = preferred == .leading ? .trailing : .leading
        let preferredShift = anchorShift(for: size, dockSide: preferred)
        let alternateShift = anchorShift(for: size, dockSide: alternate)

        // Keep the current side if it already preserves the user's placement.
        if preferredShift <= 0.5 {
            return preferred
        }

        // Otherwise choose the side that moves the anchored heads the least.
        if alternateShift + 0.5 < preferredShift {
            return alternate
        }

        return preferred
    }

    private func anchorShift(for size: NSSize, dockSide: PanelDockSide) -> CGFloat {
        let resolvedAnchor = positionManager.constrainedPanelAnchor(preferredPanelAnchor, for: size, dockSide: dockSide)
        return abs(resolvedAnchor.x - preferredPanelAnchor.x)
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
        let resolvedOrigin = positionManager.constrainedPanelOrigin(
            proposedOrigin,
            for: size,
            dockSide: manager.panelDockSide
        )

        mainPanel.setFrameOrigin(resolvedOrigin)
        panelAnchor = positionManager.panelAnchor(for: resolvedOrigin, size: size, dockSide: manager.panelDockSide)
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

    private func finishMovingPanel() {
        lastDragMouseLocation = nil
        lastDragSample = nil
        panelAnchor = positionManager.panelAnchor(
            for: mainPanel.frame.origin,
            size: mainPanel.frame.size,
            dockSide: manager.panelDockSide
        )
        preferredPanelAnchor = panelAnchor
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

        let constrainedOrigin = positionManager.constrainedPanelOrigin(origin, for: size, dockSide: manager.panelDockSide)

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
        panelAnchor = positionManager.panelAnchor(for: origin, size: size, dockSide: manager.panelDockSide)
        preferredPanelAnchor = panelAnchor
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
        manager.flushPersistence()
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

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        refreshUsage()
    }
}

private struct UsageMenuItemGroup {
    let item: NSMenuItem
    let rowView: UsageMenuRowView
}

private struct ProviderUsageSummary {
    let title: String
    let valueText: String
    let caption: String
    let progressState: UsageProgressState

    static func loading(for provider: CLIBackend) -> ProviderUsageSummary {
        ProviderUsageSummary(
            title: provider.displayName,
            valueText: "Refreshing",
            caption: "Scanning local usage sources...",
            progressState: .indeterminate
        )
    }

    static func unavailable(for provider: CLIBackend, caption: String) -> ProviderUsageSummary {
        ProviderUsageSummary(
            title: provider.displayName,
            valueText: "Unavailable",
            caption: caption,
            progressState: .unavailable
        )
    }
}

private enum UsageProgressState {
    case determinate(Double)
    case indeterminate
    case informational
    case unavailable
}

private final class UsageMenuRowView: NSView {
    private static let rowSize = NSSize(width: 264, height: 72)
    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 8

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let captionLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()

    override var intrinsicContentSize: NSSize {
        Self.rowSize
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingHead

        captionLabel.font = .systemFont(ofSize: 10)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byWordWrapping
        captionLabel.cell?.wraps = true
        captionLabel.cell?.usesSingleLineMode = false

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [titleLabel, valueLabel])
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [headerStack, progressIndicator, captionLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 5
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalInset),

            headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 10),
            captionLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ summary: ProviderUsageSummary) {
        titleLabel.stringValue = summary.title
        valueLabel.stringValue = summary.valueText
        captionLabel.stringValue = summary.caption

        switch summary.progressState {
        case .determinate(let fraction):
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 1
            progressIndicator.doubleValue = max(0, min(fraction, 1))
            progressIndicator.alphaValue = 1
        case .indeterminate:
            progressIndicator.isIndeterminate = true
            progressIndicator.alphaValue = 1
            progressIndicator.startAnimation(nil)
        case .informational:
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 1
            progressIndicator.doubleValue = 0
            progressIndicator.alphaValue = 0.2
        case .unavailable:
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 1
            progressIndicator.doubleValue = 0
            progressIndicator.alphaValue = 0.45
        }
    }
}

private final class UsageMonitor {
    private struct CodexRateLimitSnapshot {
        let primaryUsedPercent: Int?
        let secondaryUsedPercent: Int?
    }

    private struct LocalUsageWindow {
        var fiveHourTokens = 0
        var todayTokens = 0
        var fiveHourPrompts = 0
        var todayPrompts = 0
        var totalTokens = 0
        var hasUsageData = false
        var rateLimitSnapshot: CodexRateLimitSnapshot?
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "Bobble.UsageMonitor", qos: .utility)
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var cachedSummaries: [CLIBackend: ProviderUsageSummary]?
    private var lastRefreshDate: Date?
    private let cacheLifetime: TimeInterval = 60

    func refresh(force: Bool = false, completion: @escaping ([CLIBackend: ProviderUsageSummary]) -> Void) {
        queue.async {
            if !force,
               let cachedSummaries = self.cachedSummaries,
               let lastRefreshDate = self.lastRefreshDate,
               Date().timeIntervalSince(lastRefreshDate) < self.cacheLifetime {
                DispatchQueue.main.async {
                    completion(cachedSummaries)
                }
                return
            }

            let summaries = [
                CLIBackend.codex: self.loadCodexSummary(),
                CLIBackend.copilot: self.loadCopilotSummary(),
                CLIBackend.claude: self.loadClaudeSummary(),
            ]

            self.cachedSummaries = summaries
            self.lastRefreshDate = Date()

            DispatchQueue.main.async {
                completion(summaries)
            }
        }
    }

    private func loadCodexSummary() -> ProviderUsageSummary {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let databaseURL = homeURL.appendingPathComponent(".codex/state_5.sqlite", isDirectory: false)

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return .unavailable(for: .codex, caption: "No local Codex usage database found.")
        }

        let now = Date()
        let startOfDay = Self.calendar.startOfDay(for: now)
        let startOfDayTimestamp = Int(startOfDay.timeIntervalSince1970)
        let fiveHourCutoff = now.addingTimeInterval(-5 * 60 * 60)
        let fiveHourCutoffTimestamp = Int(fiveHourCutoff.timeIntervalSince1970)
        let query = """
        SELECT
            COALESCE(SUM(tokens_used), 0),
            GROUP_CONCAT(CASE WHEN updated_at >= \(min(startOfDayTimestamp, fiveHourCutoffTimestamp)) THEN rollout_path END, '\n')
        FROM threads;
        """

        guard let output = runProcess(
            executablePath: "/usr/bin/sqlite3",
            arguments: [databaseURL.path, "-separator", "\t", query]
        ) else {
            return .unavailable(for: .codex, caption: "Could not read ~/.codex/state_5.sqlite.")
        }

        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false)

        guard let totalTokens = parts.first.flatMap({ Int($0) }) else {
            return .unavailable(for: .codex, caption: "Could not parse local Codex usage data.")
        }

        let recentPaths = parts.count > 1
            ? parts[1]
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            : []

        var stats = LocalUsageWindow()
        stats.totalTokens = totalTokens

        for path in Set(recentPaths) {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = json["timestamp"] as? String,
                      let date = self.parseISODate(timestamp),
                      let type = json["type"] as? String else {
                    return
                }

                if type == "event_msg",
                   let payload = json["payload"] as? [String: Any],
                   let payloadType = payload["type"] as? String {
                    if payloadType == "user_message" {
                        if date >= fiveHourCutoff {
                            stats.fiveHourPrompts += 1
                        }
                        if date >= startOfDay {
                            stats.todayPrompts += 1
                        }
                    } else if payloadType == "token_count",
                              let info = payload["info"] as? [String: Any] {
                        let tokenTotal = self.integerValue(
                            from: (info["last_token_usage"] as? [String: Any])?["total_tokens"]
                        )
                        let hasTokenData = tokenTotal > 0

                        if date >= fiveHourCutoff {
                            stats.fiveHourTokens += tokenTotal
                        }
                        if date >= startOfDay {
                            stats.todayTokens += tokenTotal
                        }
                        if hasTokenData {
                            stats.hasUsageData = true
                        }

                        if let rateLimits = payload["rate_limits"] as? [String: Any] {
                            stats.rateLimitSnapshot = CodexRateLimitSnapshot(
                                primaryUsedPercent: self.intPercent(from: rateLimits["primary_used_percent"]),
                                secondaryUsedPercent: self.intPercent(from: rateLimits["secondary_used_percent"])
                            )
                        }
                    }
                }
            }
        }

        guard stats.hasUsageData || stats.fiveHourPrompts > 0 || stats.totalTokens > 0 else {
            return .unavailable(for: .codex, caption: "No recent Codex token events found in local session logs.")
        }

        let valueText = stats.fiveHourTokens > 0
            ? "\(Self.formatTokenCount(stats.fiveHourTokens)) tok / \(stats.fiveHourPrompts)p"
            : "\(stats.fiveHourPrompts) prompts"

        let progressState: UsageProgressState
        var usageFragments = [
            "Last 5h: \(Self.formatTokenCount(stats.fiveHourTokens)) tokens across \(stats.fiveHourPrompts) prompts.",
            "Today: \(Self.formatTokenCount(stats.todayTokens)) tokens across \(stats.todayPrompts) prompts.",
            "Local total: \(Self.formatTokenCount(stats.totalTokens)).",
        ]

        if let rateLimits = stats.rateLimitSnapshot,
           let primaryUsedPercent = rateLimits.primaryUsedPercent {
            progressState = .determinate(Double(primaryUsedPercent) / 100.0)
            usageFragments.insert("Session window: \(primaryUsedPercent)% used.", at: 0)
            if let secondaryUsedPercent = rateLimits.secondaryUsedPercent {
                usageFragments.insert("Weekly window: \(secondaryUsedPercent)% used.", at: 1)
            }
        } else {
            progressState = .informational
        }

        return ProviderUsageSummary(
            title: CLIBackend.codex.displayName,
            valueText: valueText,
            caption: usageFragments.joined(separator: " "),
            progressState: progressState
        )
    }

    private func loadClaudeSummary() -> ProviderUsageSummary {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let projectsURL = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)

        guard fileManager.fileExists(atPath: projectsURL.path) else {
            return .unavailable(for: .claude, caption: "No local Claude session logs found.")
        }

        let now = Date()
        let startOfDay = Self.calendar.startOfDay(for: now)
        let fiveHourCutoff = now.addingTimeInterval(-5 * 60 * 60)
        let earliestRelevantDate = min(startOfDay, fiveHourCutoff)

        var stats = LocalUsageWindow()
        var seenRequestIds = Set<String>()
        var seenPromptIds = Set<String>()

        guard let enumerator = fileManager.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable(for: .claude, caption: "Could not enumerate ~/.claude/projects.")
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard resourceValues.isRegularFile == true else { continue }
                if let modifiedAt = resourceValues.contentModificationDate,
                   modifiedAt < earliestRelevantDate {
                    continue
                }
            } catch {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String,
                      let timestamp = json["timestamp"] as? String,
                      let date = self.parseISODate(timestamp) else {
                    return
                }

                if type == "user",
                   let promptIdentifier = json["uuid"] as? String,
                   seenPromptIds.insert(promptIdentifier).inserted,
                   self.isClaudePromptEvent(json),
                   date >= earliestRelevantDate {
                    if date >= fiveHourCutoff {
                        stats.fiveHourPrompts += 1
                    }
                    if date >= startOfDay {
                        stats.todayPrompts += 1
                    }
                }

                guard type == "assistant",
                      let message = json["message"] as? [String: Any] else {
                    return
                }

                let requestIdentifier = (json["requestId"] as? String)
                    ?? (message["id"] as? String)
                    ?? (json["uuid"] as? String)

                guard let requestIdentifier,
                      seenRequestIds.insert(requestIdentifier).inserted,
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let billedTokens = self.integerValue(from: usage["input_tokens"])
                    + self.integerValue(from: usage["output_tokens"])
                    + self.integerValue(from: usage["cache_creation_input_tokens"])
                    + self.integerValue(from: usage["cache_read_input_tokens"])

                guard billedTokens > 0 else { return }
                stats.hasUsageData = true

                if date >= fiveHourCutoff {
                    stats.fiveHourTokens += billedTokens
                }
                if date >= startOfDay {
                    stats.todayTokens += billedTokens
                }
            }
        }

        guard stats.hasUsageData || stats.fiveHourPrompts > 0 else {
            return .unavailable(for: .claude, caption: "No recent Claude billing events found in local session logs.")
        }

        let valueText = stats.fiveHourTokens > 0
            ? "\(Self.formatTokenCount(stats.fiveHourTokens)) tok / \(stats.fiveHourPrompts)p"
            : "\(stats.fiveHourPrompts) prompts"

        return ProviderUsageSummary(
            title: CLIBackend.claude.displayName,
            valueText: valueText,
            caption: "Last 5h: \(Self.formatTokenCount(stats.fiveHourTokens)) billed tokens across \(stats.fiveHourPrompts) prompts. Today: \(Self.formatTokenCount(stats.todayTokens)) billed tokens across \(stats.todayPrompts) prompts.",
            progressState: .informational
        )
    }

    private func loadCopilotSummary() -> ProviderUsageSummary {
        let hasCLI = CLIBackend.copilot.resolvedPath() != nil

        if hasCLI {
            return .unavailable(
                for: .copilot,
                caption: "GitHub Copilot CLI is installed, but Bobble does not have a reliable local usage source for quota data yet."
            )
        }

        return .unavailable(
            for: .copilot,
            caption: "GitHub Copilot CLI is not installed, and no local usage source is available."
        )
    }

    private func parseISODate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }

        return Self.fallbackISOFormatter.date(from: value)
    }

    private func runProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func integerValue(from value: Any?) -> Int {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? Int(Double(string) ?? 0)
        default:
            return 0
        }
    }

    private func intPercent(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return max(0, min(int, 100))
        case let double as Double:
            return max(0, min(Int(double.rounded()), 100))
        case let number as NSNumber:
            return max(0, min(number.intValue, 100))
        case let string as String:
            if let int = Int(string) {
                return max(0, min(int, 100))
            }
            if let double = Double(string) {
                return max(0, min(Int(double.rounded()), 100))
            }
            return nil
        default:
            return nil
        }
    }

    private func isClaudePromptEvent(_ json: [String: Any]) -> Bool {
        guard (json["isMeta"] as? Bool) != true,
              let message = json["message"] as? [String: Any],
              let role = message["role"] as? String,
              role == "user" else {
            return false
        }

        guard self.containsMeaningfulClaudeContent(message["content"]) else {
            return false
        }

        return true
    }

    private func containsMeaningfulClaudeContent(_ value: Any?) -> Bool {
        if let content = value as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return !trimmed.contains("<command-name>")
                && !trimmed.contains("<local-command-caveat>")
        }

        if let content = value as? [[String: Any]] {
            for item in content {
                let type = (item["type"] as? String)?.lowercased()
                if type == "tool_result" {
                    continue
                }

                if let text = item["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }

                if type == "image" || type == "document" {
                    return true
                }
            }
        }

        return false
    }

    private static let calendar = Calendar.current

    private static let fallbackISOFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    private static func formatTokenCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        case 10_000...:
            return String(format: "%.0fK", Double(count) / 1_000.0)
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000.0)
        default:
            return "\(count)"
        }
    }
}

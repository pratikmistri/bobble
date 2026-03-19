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
    private var lastDragMouseLocation: NSPoint?
    private var lastDragSample: (origin: NSPoint, time: TimeInterval)?
    private var tossVelocity = CGVector.zero
    private var physicsTimer: Timer?
    private var lastPhysicsStepTime: TimeInterval?
    private var suppressNextPanelSizeUpdate = false

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
            self?.expandSession(session)
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
        manager.panelDockSide = preferredDockSideForCurrentFrame()
        panelAnchor = positionManager.constrainedPanelAnchor(panelAnchor, for: size, dockSide: manager.panelDockSide)
        let origin = positionManager.panelOrigin(for: size, anchor: panelAnchor, dockSide: manager.panelDockSide)

        // Resize panel synchronously
        mainPanel.setFrame(NSRect(origin: origin, size: size), display: true)

        // Set state in the same synchronous block — SwiftUI won't re-render
        // until the run loop cycles, by which point the frame is already correct.
        withAnimation(DesignTokens.motionLayout) {
            manager.expandedSessionId = session.id
        }
    }

    private func collapseSession() {
        guard let expandedSessionId = manager.expandedSessionId, !isCollapsingSession else { return }
        stopPhysics()
        isCollapsingSession = true

        let size = positionManager.collapsedPanelSize(count: max(manager.sessions.count, 1))

        // Keep the closing view alive long enough to animate it in place instead of
        // morphing the panel background into the returning head.
        withAnimation(DesignTokens.motionLayout) {
            manager.closingSessionId = expandedSessionId
            manager.expandedSessionId = nil
        }
        animatePanelFrame(to: size, duration: 0.34, mode: .verticalCollapse) { [weak self] in
            guard let self else { return }
            self.manager.closingSessionId = nil
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
                self.panelAnchor,
                for: finalSize,
                dockSide: self.manager.panelDockSide
            )
            let finalOrigin = self.positionManager.panelOrigin(
                for: finalSize,
                anchor: self.panelAnchor,
                dockSide: self.manager.panelDockSide
            )
            self.mainPanel.setFrame(NSRect(origin: finalOrigin, size: finalSize), display: true)
            self.isCollapsingSession = false
        }
    }

    private func openHistorySession(_ session: ChatSession) {
        stopPhysics()
        if let activeSession = manager.sessions.first(where: { $0.id == session.id }) {
            if manager.expandedSessionId == activeSession.id {
                return
            }

            if manager.expandedSessionId != nil {
                withAnimation(DesignTokens.motionLayout) {
                    manager.expandedSessionId = activeSession.id
                }
            } else {
                expandSession(activeSession)
            }
            return
        }

        _ = manager.restoreSessionFromHistory(session)
    }

    private func updatePanelSize() {
        stopPhysics()
        let size: NSSize
        if manager.expandedSessionId != nil {
            size = positionManager.expandedPanelSize(headsCount: max(manager.sessions.count, 1))
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
        let targetDockSide = preferredDockSideForCurrentFrame()
        let resolvedAnchor = positionManager.constrainedPanelAnchor(panelAnchor, for: size, dockSide: targetDockSide)
        let finalOrigin = positionManager.panelOrigin(for: size, anchor: resolvedAnchor, dockSide: targetDockSide)
        let finalFrame = NSRect(origin: finalOrigin, size: size)
        let animatedFrame: NSRect

        switch mode {
        case .fullFrame:
            panelAnchor = resolvedAnchor
            manager.panelDockSide = targetDockSide
            animatedFrame = finalFrame
        case .verticalCollapse:
            let currentFrame = mainPanel.frame
            animatedFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y,
                width: currentFrame.size.width,
                height: size.height
            )
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            mainPanel.animator().setFrame(
                animatedFrame,
                display: true
            )
        } completionHandler: {
            if mode != .fullFrame {
                self.panelAnchor = resolvedAnchor
                self.manager.panelDockSide = targetDockSide
                self.mainPanel.setFrame(finalFrame, display: true)
            }
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
        let resolvedOrigin = positionManager.constrainedPanelOrigin(
            proposedOrigin,
            for: size,
            dockSide: manager.panelDockSide
        )

        mainPanel.setFrameOrigin(resolvedOrigin)
        panelAnchor = positionManager.panelAnchor(for: resolvedOrigin, size: size, dockSide: manager.panelDockSide)
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
        startPhysicsIfNeeded()
    }

    private func preferredDockSideForCurrentFrame() -> PanelDockSide {
        positionManager.preferredDockSide(
            for: mainPanel.frame.origin,
            size: mainPanel.frame.size,
            currentSide: manager.panelDockSide
        )
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
    case unavailable
}

private final class UsageMenuRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let captionLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()

    override var intrinsicContentSize: NSSize {
        NSSize(width: 264, height: 72)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 264, height: 72))

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
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

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
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "Bobble.UsageMonitor", qos: .utility)
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let codexPlaceholderPromptLimit = 135
    private let claudePlaceholderPromptLimit = 25
    private let copilotPlaceholderPremiumRequests = 300

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
            return .unavailable(for: .codex, caption: "OpenAI docs placeholder: ~\(codexPlaceholderPromptLimit) local messages per 5h.")
        }

        let startOfDayTimestamp = Int(Self.calendar.startOfDay(for: Date()).timeIntervalSince1970)
        let query = """
        SELECT
            COALESCE(SUM(CASE WHEN updated_at >= \(startOfDayTimestamp) THEN tokens_used ELSE 0 END), 0),
            COALESCE(SUM(tokens_used), 0)
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

        guard parts.count >= 2,
              let todayTokens = Int(parts[0]),
              let totalTokens = Int(parts[1]) else {
            return .unavailable(for: .codex, caption: "OpenAI docs placeholder: ~\(codexPlaceholderPromptLimit) local messages per 5h.")
        }

        let promptCount = countCodexPrompts(since: Date().addingTimeInterval(-5 * 60 * 60))
        let fraction = Double(promptCount) / Double(codexPlaceholderPromptLimit)

        return ProviderUsageSummary(
            title: CLIBackend.codex.displayName,
            valueText: "\(promptCount)/\(codexPlaceholderPromptLimit) est",
            caption: "5h placeholder from OpenAI docs. \(Self.formatTokenCount(todayTokens)) tokens today, \(Self.formatTokenCount(totalTokens)) local total.",
            progressState: .determinate(fraction)
        )
    }

    private func loadClaudeSummary() -> ProviderUsageSummary {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let projectsURL = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)

        guard fileManager.fileExists(atPath: projectsURL.path) else {
            return .unavailable(for: .claude, caption: "No local Claude session logs found.")
        }

        let startOfDay = Self.calendar.startOfDay(for: Date())
        let fiveHourCutoff = Date().addingTimeInterval(-5 * 60 * 60)
        var todayTokens = 0
        var totalTokens = 0
        var sawUsage = false
        var seenRequestIds = Set<String>()
        var recentPromptCount = 0
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
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
            } catch {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                if let promptData = line.data(using: .utf8),
                   let promptJSON = try? JSONSerialization.jsonObject(with: promptData) as? [String: Any],
                   let type = promptJSON["type"] as? String,
                   type == "user",
                   let message = promptJSON["message"] as? [String: Any],
                   let role = message["role"] as? String,
                   role == "user",
                   let content = message["content"] as? String,
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let promptIdentifier = promptJSON["uuid"] as? String,
                   seenPromptIds.insert(promptIdentifier).inserted,
                   let timestamp = promptJSON["timestamp"] as? String,
                   let date = self.parseISODate(timestamp),
                   date >= fiveHourCutoff {
                    recentPromptCount += 1
                }

                guard line.contains("\"type\":\"assistant\""),
                      line.contains("\"usage\""),
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String,
                      type == "assistant",
                      let message = json["message"] as? [String: Any] else {
                    return
                }

                let requestIdentifier = (json["requestId"] as? String)
                    ?? (message["id"] as? String)
                    ?? (json["uuid"] as? String)

                guard let requestIdentifier, seenRequestIds.insert(requestIdentifier).inserted,
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let inputTokens = usage["input_tokens"] as? Int ?? 0
                let outputTokens = usage["output_tokens"] as? Int ?? 0
                let directTokens = inputTokens + outputTokens

                totalTokens += directTokens
                sawUsage = sawUsage || directTokens > 0

                guard let timestamp = json["timestamp"] as? String,
                      let date = self.parseISODate(timestamp) else {
                    return
                }

                if date >= startOfDay {
                    todayTokens += directTokens
                }
            }
        }

        guard sawUsage else {
            return .unavailable(for: .claude, caption: "Anthropic docs placeholder: ~\(claudePlaceholderPromptLimit) Claude Code prompts per 5h.")
        }

        let fraction = Double(recentPromptCount) / Double(claudePlaceholderPromptLimit)

        return ProviderUsageSummary(
            title: CLIBackend.claude.displayName,
            valueText: "\(recentPromptCount)/\(claudePlaceholderPromptLimit) est",
            caption: "5h placeholder from Anthropic docs. \(Self.formatTokenCount(todayTokens)) direct tokens today, \(Self.formatTokenCount(totalTokens)) total.",
            progressState: .determinate(fraction)
        )
    }

    private func loadCopilotSummary() -> ProviderUsageSummary {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let copilotLogsURL = homeURL
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/github.copilot-chat", isDirectory: true)

        let hasCLI = CLIBackend.copilot.resolvedPath() != nil
        let hasLocalLogs = fileManager.fileExists(atPath: copilotLogsURL.path)

        if hasCLI && hasLocalLogs {
            return ProviderUsageSummary(
                title: CLIBackend.copilot.displayName,
                valueText: "\(copilotPlaceholderPremiumRequests)/mo est",
                caption: "GitHub Copilot Pro placeholder from docs. Local usage is not exposed here.",
                progressState: .determinate(0)
            )
        }

        if hasCLI {
            return ProviderUsageSummary(
                title: CLIBackend.copilot.displayName,
                valueText: "\(copilotPlaceholderPremiumRequests)/mo est",
                caption: "GitHub Copilot Pro placeholder from docs. Local usage is not exposed here.",
                progressState: .determinate(0)
            )
        }

        if hasLocalLogs {
            return ProviderUsageSummary(
                title: CLIBackend.copilot.displayName,
                valueText: "\(copilotPlaceholderPremiumRequests)/mo est",
                caption: "GitHub Copilot Pro placeholder from docs. Local usage is not exposed here.",
                progressState: .determinate(0)
            )
        }

        return ProviderUsageSummary(
            title: CLIBackend.copilot.displayName,
            valueText: "\(copilotPlaceholderPremiumRequests)/mo est",
            caption: "GitHub Copilot Pro placeholder from docs. Local usage is not exposed here.",
            progressState: .determinate(0)
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

    private func countCodexPrompts(since cutoff: Date) -> Int {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let databaseURL = homeURL.appendingPathComponent(".codex/state_5.sqlite", isDirectory: false)
        guard fileManager.fileExists(atPath: databaseURL.path) else { return 0 }

        let cutoffTimestamp = Int(cutoff.timeIntervalSince1970)
        let query = "SELECT rollout_path FROM threads WHERE updated_at >= \(cutoffTimestamp);"

        guard let output = runProcess(
            executablePath: "/usr/bin/sqlite3",
            arguments: [databaseURL.path, query]
        ) else {
            return 0
        }

        let paths = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else { return 0 }

        var count = 0

        for path in paths {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String,
                      type == "event_msg",
                      let timestamp = json["timestamp"] as? String,
                      let date = self.parseISODate(timestamp),
                      date >= cutoff,
                      let payload = json["payload"] as? [String: Any],
                      let payloadType = payload["type"] as? String,
                      payloadType == "user_message" else {
                    return
                }

                count += 1
            }
        }

        return count
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

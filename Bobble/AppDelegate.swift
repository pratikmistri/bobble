import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = ChatHeadsManager()
    private let statusBarController = StatusBarController()
    private let panelCoordinator = PanelCoordinator()
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
        statusBarController.onSelectProvider = { [weak self] provider in
            self?.manager.updateSelectedProvider(provider)
        }
        statusBarController.onSelectLayoutMode = { [weak self] layoutMode in
            self?.applyLayoutMode(layoutMode)
        }
        statusBarController.onQuit = { [weak self] in
            self?.quitApp()
        }
        statusBarController.install(
            selectedProvider: manager.selectedProvider,
            selectedLayoutMode: manager.layoutMode
        )

        manager.onSelectedProviderChanged = { [weak self] provider in
            DispatchQueue.main.async {
                self?.statusBarController.updateSelectedProvider(provider)
            }
        }
        manager.onLayoutModeChanged = { [weak self] layoutMode in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusBarController.updateSelectedLayoutMode(layoutMode)
                self.handleSessionsChanged()
            }
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
                self?.panelCoordinator.movePanelWithMouse()
            },
            onHeadsDragEnded: { [weak self] in
                self?.panelCoordinator.finishMovingPanel()
            }
        )

        panelCoordinator.onDockSideChange = { [weak self] dockSide in
            self?.manager.panelDockSide = dockSide
        }
        panelCoordinator.onWindowCloseRequested = { [weak self] in
            self?.collapseSession()
        }
        panelCoordinator.install(
            rootView: AnyView(rootView),
            layoutMode: manager.layoutMode
        )

        manager.onSessionsChanged = { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleSessionsChanged()
            }
        }

        manager.onSessionAdded = { [weak self] session in
            self?.panelCoordinator.suppressNextPanelSizeUpdate = true
            self?.expandSession(session, animateStateChange: false)
        }
    }

    private func toggleSession(_ session: ChatSession) {
        if manager.expandedSessionId == session.id {
            collapseSession()
        } else if manager.expandedSessionId != nil {
            focusExpandedSession(session)
        } else {
            expandSession(session)
        }
    }

    private func expandSession(_ session: ChatSession, animateStateChange: Bool = true) {
        let expandedIndex = manager.sessions.firstIndex(where: { $0.id == session.id })
        let shouldAnimateStateChange = animateStateChange && !session.messages.isEmpty
        panelCoordinator.expand(
            sessionCount: manager.sessions.count,
            expandedIndex: expandedIndex,
            layoutMode: manager.layoutMode,
            animateStateChange: shouldAnimateStateChange
        ) { [weak self] in
            self?.manager.expandedSessionId = session.id
        }
    }

    private func collapseSession() {
        guard manager.expandedSessionId != nil, !panelCoordinator.isCollapsingSession else { return }
        panelCoordinator.collapse(sessionCount: manager.sessions.count, layoutMode: manager.layoutMode) { [weak self] in
            self?.manager.expandedSessionId = nil
        }
    }

    private func handleSessionsChanged() {
        let expandedIndex = manager.expandedSessionId.flatMap { id in
            manager.sessions.firstIndex(where: { $0.id == id })
        }
        panelCoordinator.handleSessionsChanged(
            sessionCount: manager.sessions.count,
            expandedIndex: expandedIndex,
            layoutMode: manager.layoutMode
        )
    }

    private func archiveSession(_ session: ChatSession) {
        guard manager.expandedSessionId == session.id else {
            withAnimation(DesignTokens.motionFade) {
                manager.archiveSession(session)
            }
            return
        }

        guard !panelCoordinator.isCollapsingSession else { return }
        panelCoordinator.stopPhysics()
        panelCoordinator.isCollapsingSession = true

        let remainingCount = max(manager.sessions.count - 1, 0)
        let size = panelCoordinator.collapsedPanelSize(
            count: remainingCount,
            layoutMode: manager.layoutMode
        )

        withAnimation(DesignTokens.motionLayout) {
            manager.deletingSessionId = session.id
        }

        panelCoordinator.animatePanelFrame(to: size, duration: 0.22, mode: .verticalCollapse) { [weak self] in
            guard let self else { return }

            self.panelCoordinator.suppressNextPanelSizeUpdate = true
            self.manager.archiveSession(session)
            self.panelCoordinator.applyCollapsedFrame(
                sessionCount: self.manager.sessions.count,
                layoutMode: self.manager.layoutMode
            )
            self.panelCoordinator.isCollapsingSession = false
        }
    }

    private func openHistorySession(_ session: ChatSession) {
        panelCoordinator.stopPhysics()
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
        panelCoordinator.focusExpandedSession(
            sessionCount: manager.sessions.count,
            expandedIndex: expandedIndex,
            layoutMode: manager.layoutMode,
            animateStateChange: !session.messages.isEmpty
        ) { [weak self] in
            self?.manager.expandedSessionId = session.id
        }
    }

    private func applyLayoutMode(_ layoutMode: ChatHeadsLayoutMode) {
        guard manager.layoutMode != layoutMode else { return }
        withAnimation(DesignTokens.motionLayout) {
            manager.updateLayoutMode(layoutMode)
        }
    }

    private func handleAddSessionRequest() {
        guard !panelCoordinator.isCollapsingSession else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAddSessionTimestamp >= addSessionThrottleInterval else { return }
        lastAddSessionTimestamp = now
        manager.addSession()
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

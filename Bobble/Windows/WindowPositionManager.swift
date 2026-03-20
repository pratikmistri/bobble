import AppKit

enum PanelDockSide: Equatable {
    case leading
    case trailing
}

struct WindowPositionManager {
    private let headDiameter: CGFloat = DesignTokens.headDiameter
    private let headSpacing: CGFloat = DesignTokens.headSpacing
    private let headVisualPadding: CGFloat = DesignTokens.headVisualPadding
    private let screenMargin: CGFloat = DesignTokens.screenMargin
    private let chatWidth: CGFloat = 320
    private let chatHeight: CGFloat = 480
    private let vStackSpacing: CGFloat = 8
    private let leadingOverflow: CGFloat = DesignTokens.headPreviewOverflow
    private let headDockInset: CGFloat = DesignTokens.headInset + DesignTokens.headVisualPadding

    // MARK: - Collapsed state (just heads)

    func collapsedPanelSize(count: Int) -> NSSize {
        let controlRows = 2 // add + history
        let totalRows = count + controlRows
        let inset = DesignTokens.headInset * 2
        let stackVisualOverflow = count > 0 ? headVisualPadding : 0
        let height = CGFloat(totalRows) * headDiameter
            + CGFloat(max(totalRows - 1, 0)) * headSpacing
            + stackVisualOverflow
            + inset
        let visibleWidth = headDiameter + stackVisualOverflow
        return NSSize(
            width: visibleWidth + inset + DesignTokens.headPreviewOverflow,
            height: height
        )
    }

    // MARK: - Expanded state (deck of heads + chat window)

    func expandedPanelSize(headsCount: Int) -> NSSize {
        let stackCount = max(headsCount, 0)
        let inset = DesignTokens.headInset * 2

        let addH = headDiameter
        let historyH = headDiameter
        let stackH = stackCount > 0
            ? (CGFloat(stackCount) * headDiameter)
                + (CGFloat(stackCount - 1) * headSpacing)
                + headVisualPadding
            : 0
        let headsGap = stackCount > 0 ? headSpacing : 0
        let controlsGap = headSpacing
        let headsSection = inset + addH + controlsGap + historyH + headsGap + stackH

        let totalH = headsSection + vStackSpacing + chatHeight
        return NSSize(
            width: chatWidth + DesignTokens.headPreviewOverflow,
            height: totalH
        )
    }

    // MARK: - Panel anchor and origin

    func defaultPanelAnchor() -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(containing: mouseLocation) ?? NSScreen.main else { return .zero }
        let frame = constrainedScreenFrame(for: screen)
        return NSPoint(
            x: frame.maxX - headDockInset,
            y: frame.minY
        )
    }

    func constrainedPanelAnchor(_ anchor: NSPoint, for size: NSSize, dockSide: PanelDockSide) -> NSPoint {
        let origin = panelOrigin(for: size, anchor: anchor, dockSide: dockSide)
        let constrainedOrigin = constrainedPanelOrigin(origin, for: size, dockSide: dockSide)
        return panelAnchor(for: constrainedOrigin, size: size, dockSide: dockSide)
    }

    func panelAnchor(for origin: NSPoint, size: NSSize, dockSide: PanelDockSide) -> NSPoint {
        switch dockSide {
        case .leading:
            return NSPoint(x: origin.x + headDockInset, y: origin.y)
        case .trailing:
            return NSPoint(x: origin.x + size.width - headDockInset, y: origin.y)
        }
    }

    func constrainedPanelOrigin(_ origin: NSPoint, for size: NSSize, dockSide: PanelDockSide) -> NSPoint {
        let visibleFrame = visibleContentFrame(for: origin, size: size, dockSide: dockSide)
        let referencePoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)

        guard let screen = screen(containing: referencePoint) ?? nearestScreen(to: referencePoint) else {
            return origin
        }

        let screenFrame = constrainedScreenFrame(for: screen)
        let minOriginX: CGFloat
        let maxOriginX: CGFloat

        switch dockSide {
        case .leading:
            minOriginX = screenFrame.minX
            maxOriginX = screenFrame.maxX - (size.width - leadingOverflow)
        case .trailing:
            minOriginX = screenFrame.minX - leadingOverflow
            maxOriginX = screenFrame.maxX - size.width
        }

        let minOriginY = screenFrame.minY
        let maxOriginY = screenFrame.maxY - size.height

        return NSPoint(
            x: min(max(origin.x, minOriginX), maxOriginX),
            y: min(max(origin.y, minOriginY), maxOriginY)
        )
    }

    func panelOrigin(for size: NSSize, anchor: NSPoint, dockSide: PanelDockSide) -> NSPoint {
        let proposedOrigin: NSPoint

        switch dockSide {
        case .leading:
            proposedOrigin = NSPoint(x: anchor.x - headDockInset, y: anchor.y)
        case .trailing:
            proposedOrigin = NSPoint(x: anchor.x + headDockInset - size.width, y: anchor.y)
        }

        return constrainedPanelOrigin(proposedOrigin, for: size, dockSide: dockSide)
    }

    func preferredDockSide(for origin: NSPoint, size: NSSize, currentSide: PanelDockSide) -> PanelDockSide {
        let visibleFrame = visibleContentFrame(for: origin, size: size, dockSide: currentSide)
        let referencePoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)

        guard let screen = screen(containing: referencePoint) ?? nearestScreen(to: referencePoint) else {
            return currentSide
        }

        return visibleFrame.midX <= constrainedScreenFrame(for: screen).midX ? .leading : .trailing
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    private func constrainedScreenFrame(for screen: NSScreen) -> NSRect {
        screen.frame.insetBy(dx: screenMargin, dy: screenMargin)
    }

    private func visibleContentFrame(for origin: NSPoint, size: NSSize, dockSide: PanelDockSide) -> NSRect {
        let contentWidth = max(size.width - leadingOverflow, 0)

        switch dockSide {
        case .leading:
            return NSRect(
                x: origin.x,
                y: origin.y,
                width: contentWidth,
                height: size.height
            )
        case .trailing:
            return NSRect(
                x: origin.x + leadingOverflow,
                y: origin.y,
                width: contentWidth,
                height: size.height
            )
        }
    }

    private func nearestScreen(to point: NSPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        }
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

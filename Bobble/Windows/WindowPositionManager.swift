import AppKit

struct WindowPositionManager {
    private let headDiameter: CGFloat = DesignTokens.headDiameter
    private let headSpacing: CGFloat = DesignTokens.headSpacing
    private let headVisualPadding: CGFloat = DesignTokens.headVisualPadding
    private let screenMargin: CGFloat = DesignTokens.screenMargin
    private let chatWidth: CGFloat = 320
    private let chatHeight: CGFloat = 480
    private let vStackSpacing: CGFloat = 8
    private let leadingOverflow: CGFloat = DesignTokens.headPreviewOverflow

    // MARK: - Collapsed state (just heads)

    func collapsedPanelSize(count: Int) -> NSSize {
        let totalHeads = count + 1 // +1 for add button
        let inset = DesignTokens.headInset * 2
        let stackVisualOverflow = count > 0 ? headVisualPadding * 2 : 0
        let height = CGFloat(totalHeads) * headDiameter
            + CGFloat(totalHeads - 1) * headSpacing
            + stackVisualOverflow
            + inset
        let headsWidth = headDiameter + stackVisualOverflow
        return NSSize(
            width: headsWidth + inset + DesignTokens.headPreviewOverflow,
            height: height
        )
    }

    // MARK: - Expanded state (deck of heads + chat window)

    func expandedPanelSize(headsCount: Int) -> NSSize {
        let nonExpanded = headsCount - 1
        let inset = DesignTokens.headInset * 2

        // Heads section: add button + deck of non-expanded heads
        let addH = headDiameter
        let deckH = nonExpanded > 0
            ? headDiameter + CGFloat(nonExpanded - 1) * DesignTokens.deckOffset + (headVisualPadding * 2)
            : 0
        let headsGap = nonExpanded > 0 ? headSpacing : 0
        let headsSection = inset + addH + headsGap + deckH

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
            x: frame.maxX,
            y: frame.minY
        )
    }

    func constrainedPanelAnchor(_ anchor: NSPoint, for size: NSSize) -> NSPoint {
        let origin = NSPoint(x: anchor.x - size.width, y: anchor.y)
        let constrainedOrigin = constrainedPanelOrigin(origin, for: size)
        return panelAnchor(for: constrainedOrigin, size: size)
    }

    func panelAnchor(for origin: NSPoint, size: NSSize) -> NSPoint {
        NSPoint(x: origin.x + size.width, y: origin.y)
    }

    func constrainedPanelOrigin(_ origin: NSPoint, for size: NSSize) -> NSPoint {
        let visibleFrame = visibleContentFrame(for: origin, size: size)
        let referencePoint = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)

        guard let screen = screen(containing: referencePoint) ?? nearestScreen(to: referencePoint) else {
            return origin
        }

        let screenFrame = constrainedScreenFrame(for: screen)
        let minOriginX = screenFrame.minX - leadingOverflow
        let maxOriginX = screenFrame.maxX - size.width
        let minOriginY = screenFrame.minY
        let maxOriginY = screenFrame.maxY - size.height

        return NSPoint(
            x: min(max(origin.x, minOriginX), maxOriginX),
            y: min(max(origin.y, minOriginY), maxOriginY)
        )
    }

    func panelOrigin(for size: NSSize, anchor: NSPoint) -> NSPoint {
        let proposedOrigin = NSPoint(x: anchor.x - size.width, y: anchor.y)
        return constrainedPanelOrigin(proposedOrigin, for: size)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    private func constrainedScreenFrame(for screen: NSScreen) -> NSRect {
        screen.frame.insetBy(dx: screenMargin, dy: screenMargin)
    }

    private func visibleContentFrame(for origin: NSPoint, size: NSSize) -> NSRect {
        NSRect(
            x: origin.x + leadingOverflow,
            y: origin.y,
            width: max(size.width - leadingOverflow, 0),
            height: size.height
        )
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

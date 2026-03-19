import AppKit

struct WindowPositionManager {
    private let headDiameter: CGFloat = DesignTokens.headDiameter
    private let headSpacing: CGFloat = DesignTokens.headSpacing
    private let headVisualPadding: CGFloat = DesignTokens.headVisualPadding
    private let screenMargin: CGFloat = DesignTokens.screenMargin
    private let chatWidth: CGFloat = 320
    private let chatHeight: CGFloat = 480
    private let vStackSpacing: CGFloat = 8

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

    // MARK: - Panel origin (anchored at bottom-right of screen)

    func panelOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        let x = frame.maxX - size.width - screenMargin
        let y = frame.minY + screenMargin
        return NSPoint(x: x, y: y)
    }
}

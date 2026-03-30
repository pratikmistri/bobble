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
    private let leadingOverflow: CGFloat = DesignTokens.headPreviewOverflow
    private let headDockInset: CGFloat = DesignTokens.headInset + DesignTokens.headVisualPadding
    private var maxReasonableExpandedHorizontalWidth: CGFloat {
        let inset = DesignTokens.headInset * 2
        let controlWidth = DesignTokens.headControlDiameter
        let maxDeckHeadsPerSide = DesignTokens.maxHorizontalExpandedDeckHeadsPerSide
        let leftDeck = deckStackLength(for: maxDeckHeadsPerSide)
        let rightDeck = deckStackLength(for: maxDeckHeadsPerSide)
        let interColumnSpacing = DesignTokens.addHistoryControlSpacing + (DesignTokens.headSpacing * 3)
        // add + history + left deck + chat + right deck

        return inset
            + controlWidth
            + controlWidth
            + leftDeck
            + chatWidth
            + rightDeck
            + interColumnSpacing
            + leadingOverflow
    }

    // MARK: - Collapsed state (just heads)

    func collapsedPanelSize(count: Int, layoutMode: ChatHeadsLayoutMode) -> NSSize {
        switch layoutMode {
        case .vertical:
            return collapsedPanelSizeVertical(count: count)
        case .horizontal:
            return collapsedPanelSizeHorizontal(count: count)
        }
    }

    private func collapsedPanelSizeVertical(count: Int) -> NSSize {
        let inset = DesignTokens.headInset * 2
        let addControlHeight = DesignTokens.headControlDiameter
        let historyControlHeight = DesignTokens.headControlDiameter
        let headStackHeight = collapsedHeadStackLength(for: count)

        var rows: [CGFloat] = [addControlHeight, historyControlHeight]
        if headStackHeight > 0 {
            rows.append(headStackHeight)
        }

        let height = rows.reduce(0, +)
            + spacedDistance(
                itemCount: rows.count,
                leadingGap: DesignTokens.addHistoryControlSpacing,
                defaultGap: DesignTokens.verticalControlSpacing
            )
            + inset

        let stackVisualOverflow = count > 0 ? headVisualPadding : 0
        let visibleWidth = headDiameter + stackVisualOverflow
        return NSSize(
            width: visibleWidth + inset + DesignTokens.headPreviewOverflow,
            height: height
        )
    }

    private func collapsedPanelSizeHorizontal(count: Int) -> NSSize {
        let inset = DesignTokens.headInset * 2
        let controlWidth = DesignTokens.headControlDiameter
        let addControlWidth = controlWidth
        let historyControlWidth = controlWidth
        let visibleHeadsCount = min(max(count, 0), DesignTokens.maxHorizontalCollapsedVisibleHeads)
        let headStackWidth = collapsedHeadStackLength(for: visibleHeadsCount)

        var columns: [CGFloat] = [addControlWidth, historyControlWidth]
        if headStackWidth > 0 {
            columns.append(headStackWidth)
        }

        let width = inset
            + columns.reduce(0, +)
            + spacedDistance(
                itemCount: columns.count,
                leadingGap: DesignTokens.addHistoryControlSpacing,
                defaultGap: headSpacing
            )
            + DesignTokens.headPreviewOverflow
        let height = inset + controlWidth

        return NSSize(width: width, height: height)
    }

    // MARK: - Expanded state (inline chat + stacked controls)

    func expandedPanelSize(
        headsCount: Int,
        expandedIndex: Int? = nil,
        layoutMode: ChatHeadsLayoutMode
    ) -> NSSize {
        switch layoutMode {
        case .vertical:
            return expandedPanelSizeVertical(headsCount: headsCount, expandedIndex: expandedIndex)
        case .horizontal:
            return expandedPanelSizeHorizontal(headsCount: headsCount, expandedIndex: expandedIndex)
        }
    }

    private func expandedPanelSizeVertical(headsCount: Int, expandedIndex: Int? = nil) -> NSSize {
        let stackCount = max(headsCount, 0)
        let inset = DesignTokens.headInset * 2

        let clampedExpandedIndex: Int? = {
            guard let expandedIndex, stackCount > 0 else { return nil }
            return min(max(expandedIndex, 0), stackCount - 1)
        }()
        let aboveCount = clampedExpandedIndex ?? 0
        let belowCount = clampedExpandedIndex.map { max(stackCount - $0 - 1, 0) } ?? 0

        let addH = DesignTokens.headControlDiameter
        let historyH = DesignTokens.headControlDiameter
        let topStackCount = aboveCount
        let bottomStackCount = belowCount

        var rows: [CGFloat] = [addH, historyH]
        if topStackCount > 0 {
            rows.append(deckStackLength(for: topStackCount))
        }
        rows.append(chatHeight)
        if bottomStackCount > 0 {
            rows.append(deckStackLength(for: bottomStackCount))
        }

        let rowsHeight = rows.reduce(0, +)
        let rowSpacing = spacedDistance(
            itemCount: rows.count,
            leadingGap: DesignTokens.addHistoryControlSpacing,
            defaultGap: DesignTokens.verticalControlSpacing
        )
        let totalH = inset + rowsHeight + rowSpacing
        return NSSize(
            width: inset + chatWidth + DesignTokens.headPreviewOverflow,
            height: totalH
        )
    }

    private func expandedPanelSizeHorizontal(headsCount: Int, expandedIndex: Int? = nil) -> NSSize {
        let stackCount = max(headsCount, 0)
        let inset = DesignTokens.headInset * 2

        let clampedExpandedIndex: Int? = {
            guard let expandedIndex, stackCount > 0 else { return nil }
            return min(max(expandedIndex, 0), stackCount - 1)
        }()
        let beforeCount = clampedExpandedIndex ?? 0
        let afterCount = clampedExpandedIndex.map { max(stackCount - $0 - 1, 0) } ?? 0
        let visibleBeforeCount = min(beforeCount, DesignTokens.maxHorizontalExpandedDeckHeadsPerSide)
        let visibleAfterCount = min(afterCount, DesignTokens.maxHorizontalExpandedDeckHeadsPerSide)

        let controlWidth = DesignTokens.headControlDiameter
        var columns: [CGFloat] = [controlWidth, controlWidth]

        let beforeStackWidth = deckStackLength(for: visibleBeforeCount)
        if beforeStackWidth > 0 {
            columns.append(beforeStackWidth)
        }

        columns.append(chatWidth)

        let afterStackWidth = deckStackLength(for: visibleAfterCount)
        if afterStackWidth > 0 {
            columns.append(afterStackWidth)
        }

        let width = inset
            + columns.reduce(0, +)
            + spacedDistance(
                itemCount: columns.count,
                leadingGap: DesignTokens.addHistoryControlSpacing,
                defaultGap: headSpacing
            )
            + DesignTokens.headPreviewOverflow
        let height = inset + max(chatHeight, controlWidth)

        return NSSize(width: width, height: height)
    }


    // Prevent oversized windows from forcing AppKit into repeated constraint passes.
    func clampedPanelSize(_ size: NSSize, anchor: NSPoint) -> NSSize {
        guard let screen = screen(containing: anchor) ?? nearestScreen(to: anchor) else {
            return size
        }

        let frame = constrainedScreenFrame(for: screen)
        let minHeight = (headDiameter * 2) + headSpacing + (DesignTokens.headInset * 2)
        let minWidth = headDiameter + (DesignTokens.headInset * 2) + leadingOverflow
        let maxHeight = max(frame.height, minHeight)
        let maxScreenBoundedWidth = max(frame.width + leadingOverflow, minWidth)
        let maxWidth = min(maxScreenBoundedWidth, maxReasonableExpandedHorizontalWidth)

        return NSSize(
            width: min(size.width, maxWidth),
            height: min(size.height, maxHeight)
        )
    }
    private func deckStackLength(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return headDiameter + (CGFloat(count - 1) * DesignTokens.deckOffset) + headVisualPadding
    }

    private func collapsedHeadStackLength(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return DesignTokens.headControlDiameter * CGFloat(count)
            + CGFloat(count - 1) * headSpacing
    }

    private func spacedDistance(itemCount: Int, leadingGap: CGFloat, defaultGap: CGFloat) -> CGFloat {
        guard itemCount > 1 else { return 0 }
        return leadingGap + CGFloat(max(itemCount - 2, 0)) * defaultGap
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

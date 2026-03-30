import XCTest
@testable import Bobble

final class WindowPositionManagerLayoutTests: XCTestCase {
    private let positionManager = WindowPositionManager()

    func testCollapsedLayoutModeAffectsDominantDimension() {
        let count = 4
        let vertical = positionManager.collapsedPanelSize(count: count, layoutMode: .vertical)
        let horizontal = positionManager.collapsedPanelSize(count: count, layoutMode: .horizontal)

        XCTAssertGreaterThan(vertical.height, horizontal.height)
        XCTAssertGreaterThan(horizontal.width, vertical.width)
    }

    func testExpandedLayoutModeAffectsDominantDimension() {
        let headsCount = 6
        let expandedIndex = 3
        let vertical = positionManager.expandedPanelSize(
            headsCount: headsCount,
            expandedIndex: expandedIndex,
            layoutMode: .vertical
        )
        let horizontal = positionManager.expandedPanelSize(
            headsCount: headsCount,
            expandedIndex: expandedIndex,
            layoutMode: .horizontal
        )

        XCTAssertGreaterThan(vertical.height, horizontal.height)
        XCTAssertGreaterThan(horizontal.width, vertical.width)
    }

    func testCollapsedAndExpandedSizesRemainPositiveForEdgeCases() {
        for layoutMode in ChatHeadsLayoutMode.allCases {
            let collapsedZero = positionManager.collapsedPanelSize(count: 0, layoutMode: layoutMode)
            XCTAssertGreaterThan(collapsedZero.width, 0)
            XCTAssertGreaterThan(collapsedZero.height, 0)

            let collapsedOne = positionManager.collapsedPanelSize(count: 1, layoutMode: layoutMode)
            XCTAssertGreaterThan(collapsedOne.width, 0)
            XCTAssertGreaterThan(collapsedOne.height, 0)

            let expandedOne = positionManager.expandedPanelSize(
                headsCount: 1,
                expandedIndex: 0,
                layoutMode: layoutMode
            )
            XCTAssertGreaterThan(expandedOne.width, 0)
            XCTAssertGreaterThan(expandedOne.height, 0)
        }
    }

    func testHorizontalCollapsedSizeCapsVisibleHeads() {
        let cappedCount = DesignTokens.maxHorizontalCollapsedVisibleHeads
        let atCap = positionManager.collapsedPanelSize(count: cappedCount, layoutMode: .horizontal)
        let aboveCap = positionManager.collapsedPanelSize(count: cappedCount + 40, layoutMode: .horizontal)

        XCTAssertEqual(aboveCap.width, atCap.width, accuracy: 0.001)
        XCTAssertEqual(aboveCap.height, atCap.height, accuracy: 0.001)
    }

    func testHorizontalExpandedSizeCapsDeckHeadsPerSide() {
        let cap = DesignTokens.maxHorizontalExpandedDeckHeadsPerSide
        let baselineHeadsCount = (cap * 2) + 1
        let baselineExpandedIndex = cap

        let baseline = positionManager.expandedPanelSize(
            headsCount: baselineHeadsCount,
            expandedIndex: baselineExpandedIndex,
            layoutMode: .horizontal
        )

        let oversized = positionManager.expandedPanelSize(
            headsCount: 200,
            expandedIndex: 100,
            layoutMode: .horizontal
        )

        XCTAssertEqual(oversized.width, baseline.width, accuracy: 0.001)
        XCTAssertEqual(oversized.height, baseline.height, accuracy: 0.001)
    }

    func testVerticalExpandedWidthIncludesInsetPadding() {
        let size = positionManager.expandedPanelSize(
            headsCount: 1,
            expandedIndex: 0,
            layoutMode: .vertical
        )
        let expectedWidth = 320 + (DesignTokens.headInset * 2) + DesignTokens.headPreviewOverflow

        XCTAssertEqual(size.width, expectedWidth, accuracy: 0.001)
    }
}

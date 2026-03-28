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
}

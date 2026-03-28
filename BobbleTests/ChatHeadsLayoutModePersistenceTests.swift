import XCTest
@testable import Bobble

final class ChatHeadsLayoutModePersistenceTests: XCTestCase {
    func testDefaultsToVerticalWhenNoStoredValueExists() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { clearDefaults(suiteName: suiteName) }

        let manager = ChatHeadsManager(userDefaults: defaults)
        XCTAssertEqual(manager.layoutMode, .vertical)
    }

    func testRestoresPersistedLayoutMode() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { clearDefaults(suiteName: suiteName) }

        let manager = ChatHeadsManager(userDefaults: defaults)
        manager.updateLayoutMode(.horizontal)

        let restoredManager = ChatHeadsManager(userDefaults: defaults)
        XCTAssertEqual(restoredManager.layoutMode, .horizontal)
    }

    func testInvalidStoredLayoutFallsBackToVertical() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { clearDefaults(suiteName: suiteName) }

        defaults.set("diagonal", forKey: ChatHeadsManager.layoutModeDefaultsKey)
        let manager = ChatHeadsManager(userDefaults: defaults)

        XCTAssertEqual(manager.layoutMode, .vertical)
    }

    private func makeIsolatedDefaults() -> (String, UserDefaults) {
        let suiteName = "ChatHeadsLayoutModePersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated UserDefaults suite to be created")
            return (suiteName, .standard)
        }
        return (suiteName, defaults)
    }

    private func clearDefaults(suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

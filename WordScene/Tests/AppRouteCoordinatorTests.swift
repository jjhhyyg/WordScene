import XCTest
@testable import WordScene

@MainActor
final class AppRouteCoordinatorTests: XCTestCase {
    func testRouteCoordinatorParsesShareTranslationURL() throws {
        let coordinator = AppRouteCoordinator()
        let id = UUID()

        coordinator.open(
            url: try XCTUnwrap(URL(string: "wordscene://share-translation?id=\(id.uuidString)"))
        )

        XCTAssertEqual(coordinator.pendingShareHandoffID, id)
        XCTAssertEqual(coordinator.consumePendingShareHandoffID(), id)
        XCTAssertNil(coordinator.pendingShareHandoffID)
    }

    func testRouteCoordinatorIgnoresUnrelatedURL() throws {
        let coordinator = AppRouteCoordinator()

        coordinator.open(url: try XCTUnwrap(URL(string: "wordscene://library?id=123")))

        XCTAssertNil(coordinator.pendingShareHandoffID)
    }
}

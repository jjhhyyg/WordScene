import XCTest
@testable import WordScene

final class AppBuildInfoTests: XCTestCase {
    func testUsesBundleMetadataForSmokeTestDisplay() {
        let info = AppBuildInfo(
            infoDictionary: [
                "CFBundleDisplayName": "译笺",
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45"
            ]
        )

        XCTAssertEqual(info.displayName, "译笺")
        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.build, "45")
        XCTAssertEqual(info.smokeTestDisplayValue, "译笺 1.2.3 (45)")
    }

    func testFallsBackWhenBundleMetadataIsMissing() {
        let info = AppBuildInfo(infoDictionary: [:])

        XCTAssertEqual(info.displayName, "WordScene")
        XCTAssertEqual(info.version, "1.0.0")
        XCTAssertEqual(info.build, "1")
        XCTAssertEqual(info.smokeTestDisplayValue, "WordScene 1.0.0 (1)")
    }
}

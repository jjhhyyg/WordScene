import XCTest
@testable import WordScene

final class CloudKitSchemaInitializationTests: XCTestCase {
    func testInitializeCloudKitDevelopmentSchema() throws {
        guard Self.flag("WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA") else {
            throw XCTSkip("Set WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA=1 to initialize the CloudKit development schema.")
        }

        try CoreDataMemoryStore.initializeCloudKitDevelopmentSchema(
            dryRun: Self.flag("WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_DRY_RUN"),
            printsSchema: Self.flag("WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_PRINT")
        )
    }

    private static func flag(_ key: String) -> Bool {
        if ProcessInfo.processInfo.environment[key] == "1" {
            return true
        }

        let value = Bundle(for: Self.self).object(forInfoDictionaryKey: key)
        return value as? String == "1" || value as? Bool == true
    }
}

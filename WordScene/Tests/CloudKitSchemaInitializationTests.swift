import XCTest
@testable import WordScene

final class CloudKitSchemaInitializationTests: XCTestCase {
    func testInitializeCloudKitDevelopmentSchema() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA"] == "1" else {
            throw XCTSkip("Set WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA=1 to initialize the CloudKit development schema.")
        }

        try CoreDataMemoryStore.initializeCloudKitDevelopmentSchema(
            dryRun: environment["WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_DRY_RUN"] == "1",
            printsSchema: environment["WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_PRINT"] == "1"
        )
    }
}

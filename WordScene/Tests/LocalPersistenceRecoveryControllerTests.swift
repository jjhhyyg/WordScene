import XCTest
@testable import WordScene

final class LocalPersistenceRecoveryControllerTests: XCTestCase {
    func testPrepareBackupExportsRawLocalDocuments() throws {
        let suiteName = "LocalPersistenceRecoveryControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let memoryData = Data("{not memory json".utf8)
        let historyData = Data("{not history json".utf8)
        defaults.set(memoryData, forKey: "memoryLibrary")
        defaults.set(historyData, forKey: "translationHistory")
        let controller = LocalPersistenceRecoveryController(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let backup = try controller.prepareBackup()

        XCTAssertEqual(backup.fileName, "wordscene-local-backup-20270115-080000.json")
        XCTAssertEqual(backup.documentCount, 2)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: backup.data) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        let documents = try XCTUnwrap(object["documents"] as? [[String: Any]])
        XCTAssertEqual(documents.first { $0["key"] as? String == "memoryLibrary" }?["data_base64"] as? String, memoryData.base64EncodedString())
        XCTAssertEqual(documents.first { $0["key"] as? String == "translationHistory" }?["data_base64"] as? String, historyData.base64EncodedString())
    }

    func testResetLocalDocumentsRemovesOnlyKnownLegacyKeys() {
        let suiteName = "LocalPersistenceRecoveryControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data("memory".utf8), forKey: "memoryLibrary")
        defaults.set(Data("history".utf8), forKey: "translationHistory")
        defaults.set(Data("other".utf8), forKey: "unrelated")
        let controller = LocalPersistenceRecoveryController(defaults: defaults)

        let resetCount = controller.resetLocalDocuments()

        XCTAssertEqual(resetCount, 2)
        XCTAssertNil(defaults.data(forKey: "memoryLibrary"))
        XCTAssertNil(defaults.data(forKey: "translationHistory"))
        XCTAssertEqual(defaults.data(forKey: "unrelated"), Data("other".utf8))
    }
}

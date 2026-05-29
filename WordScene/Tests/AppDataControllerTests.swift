import Combine
import XCTest
@testable import WordScene

final class AppDataControllerTests: XCTestCase {
    private enum StoreBootstrapError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Core Data store unavailable"
        }
    }

    private var temporaryDefaults: UserDefaults {
        let suiteName = "WordSceneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testRepositoriesShareInjectedCoreDataStore() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(coreDataStore: coreDataStore)
        let memoryItem = MemoryItem(
            sourceText: "shared",
            translatedText: "共享",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let historyRecord = TranslationRecord(
            sourceText: "history",
            translatedText: "历史",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        controller.memoryLibrary.save([memoryItem])
        controller.translationHistory.save([historyRecord])

        XCTAssertEqual(try coreDataStore.loadActiveItems(), [memoryItem])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [historyRecord])
    }

    func testReportsPrimaryPersistenceWhenCoreDataLoads() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier),
            syncEventStore: CloudKitSyncEventStore(userDefaults: temporaryDefaults)
        )

        XCTAssertEqual(
            controller.persistenceStatus,
            .coreDataAvailable(syncMode: .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier))
        )
        XCTAssertEqual(controller.persistenceStatus.title, "Core Data 已启用")
        XCTAssertEqual(
            controller.syncStatus,
            .cloudKitConfigured(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier)
        )
        XCTAssertEqual(controller.syncStatus.title, "iCloud 同步已配置")
    }

    func testReportsFallbackPersistenceWhenCoreDataBootstrapFails() {
        let controller = AppDataController(coreDataStoreFactory: {
            throw StoreBootstrapError.unavailable
        })

        XCTAssertEqual(
            controller.persistenceStatus,
            .legacyFallback(reason: "Core Data store unavailable")
        )
        XCTAssertEqual(controller.syncStatus, .unavailable(reason: "Core Data store unavailable"))
        XCTAssertEqual(controller.syncStatus.title, "同步不可用")
    }

    func testReportsLocalOnlySyncStatusWhenCloudKitIsNotAvailable() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .localOnly
        )

        XCTAssertEqual(controller.syncStatus, .localOnly)
        XCTAssertEqual(controller.syncStatus.title, "仅本机存储")
        XCTAssertTrue(controller.syncStatus.message.contains("不会通过 iCloud 同步"))
    }

    func testCloudSyncEventStatusStartsWaitingForSignedCloudKitStores() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier),
            syncEventStore: CloudKitSyncEventStore(userDefaults: temporaryDefaults)
        )

        XCTAssertEqual(controller.syncEventMonitor.status.title, "等待 iCloud 同步事件")
        XCTAssertTrue(controller.syncEventMonitor.status.message.contains("不能证明多端已同步"))
    }

    func testCloudSyncEventStatusRecordsSuccessfulImportEvent() {
        let monitor = CloudKitSyncEventMonitor(
            syncStatus: .cloudKitConfigured(containerIdentifier: "iCloud.test"),
            eventStore: CloudKitSyncEventStore(userDefaults: temporaryDefaults)
        )

        monitor.record(CloudSyncEvent(
            kind: .importFromCloud,
            startDate: Date(timeIntervalSince1970: 10),
            endDate: Date(timeIntervalSince1970: 20),
            succeeded: true,
            errorDescription: nil
        ))

        XCTAssertEqual(monitor.status.title, "最近同步成功")
        XCTAssertTrue(monitor.status.message.contains("从 iCloud 导入"))
    }

    func testCloudSyncEventStatusRecordsFailedExportEvent() {
        let monitor = CloudKitSyncEventMonitor(
            syncStatus: .cloudKitConfigured(containerIdentifier: "iCloud.test"),
            eventStore: CloudKitSyncEventStore(userDefaults: temporaryDefaults)
        )

        monitor.record(CloudSyncEvent(
            kind: .exportToCloud,
            startDate: Date(timeIntervalSince1970: 10),
            endDate: Date(timeIntervalSince1970: 20),
            succeeded: false,
            errorDescription: "quota exceeded"
        ))

        XCTAssertEqual(monitor.status.title, "同步出现错误")
        XCTAssertTrue(monitor.status.message.contains("向 iCloud 上传"))
        XCTAssertTrue(monitor.status.message.contains("quota exceeded"))
    }

    func testCloudSyncEventStatusRestoresLastRecordedEvent() {
        let eventStore = CloudKitSyncEventStore(userDefaults: temporaryDefaults)
        let notificationCenter = NotificationCenter()
        let monitor = CloudKitSyncEventMonitor(
            syncStatus: .cloudKitConfigured(containerIdentifier: "iCloud.test"),
            eventStore: eventStore,
            notificationCenter: notificationCenter
        )
        monitor.record(CloudSyncEvent(
            kind: .importFromCloud,
            startDate: Date(timeIntervalSince1970: 10),
            endDate: Date(timeIntervalSince1970: 20),
            succeeded: true,
            errorDescription: nil
        ))

        let restoredMonitor = CloudKitSyncEventMonitor(
            syncStatus: .cloudKitConfigured(containerIdentifier: "iCloud.test"),
            eventStore: eventStore,
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(restoredMonitor.status.title, "最近同步成功")
        XCTAssertTrue(restoredMonitor.status.message.contains("从 iCloud 导入"))
    }

    func testLocalOnlySyncStatusDoesNotRestoreCloudEvents() {
        let eventStore = CloudKitSyncEventStore(userDefaults: temporaryDefaults)
        eventStore.save(CloudSyncEvent(
            kind: .exportToCloud,
            startDate: Date(timeIntervalSince1970: 10),
            endDate: Date(timeIntervalSince1970: 20),
            succeeded: true,
            errorDescription: nil
        ))

        let monitor = CloudKitSyncEventMonitor(
            syncStatus: .localOnly,
            eventStore: eventStore,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(monitor.status.title, "没有同步事件")
        XCTAssertTrue(monitor.status.message.contains("仅本机存储"))
    }

    func testDataChangeMonitorPublishesPersistentStoreRemoteChanges() {
        let notificationCenter = NotificationCenter()
        let monitor = AppDataChangeMonitor(notificationCenter: notificationCenter)
        let expectation = expectation(description: "revision changes after remote store notification")
        let cancellable = monitor.$revision.dropFirst().sink { revision in
            XCTAssertEqual(revision, 1)
            expectation.fulfill()
        }

        notificationCenter.post(name: .NSPersistentStoreRemoteChange, object: nil)

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }
}

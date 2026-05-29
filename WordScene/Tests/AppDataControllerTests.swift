import Combine
import Network
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

    func testLocalRecoveryResetDoesNotRemoveCurrentCoreDataLibraryOrHistory() throws {
        let suiteName = "AppDataControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data("legacy memory".utf8), forKey: "memoryLibrary")
        defaults.set(Data("legacy history".utf8), forKey: "translationHistory")
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(
            coreDataStore: coreDataStore,
            localDocumentRecovery: LocalPersistenceRecoveryController(defaults: defaults)
        )
        let memoryItem = MemoryItem(
            sourceText: "current",
            translatedText: "当前",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let historyRecord = TranslationRecord(
            sourceText: "recent",
            translatedText: "最近",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        try controller.memoryLibrary.saveOrThrow([memoryItem])
        try controller.translationHistory.saveOrThrow([historyRecord])
        let resetCount = controller.localDocumentRecovery.resetLocalDocuments()

        XCTAssertEqual(resetCount, 2)
        XCTAssertNil(defaults.data(forKey: "memoryLibrary"))
        XCTAssertNil(defaults.data(forKey: "translationHistory"))
        XCTAssertEqual(try controller.memoryLibrary.loadOrThrow(), [memoryItem])
        XCTAssertEqual(try controller.translationHistory.loadOrThrow(), [historyRecord])
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

    func testCloudKitBootstrapFailureRetriesCoreDataLocalOnlyBeforeLegacyFallback() throws {
        var bootstrapAttempts = 0
        let localStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(
            coreDataStoreFactory: {
                bootstrapAttempts += 1
                if bootstrapAttempts == 1 {
                    throw StoreBootstrapError.unavailable
                }
                return localStore
            },
            syncMode: .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier)
        )
        let item = MemoryItem(
            sourceText: "offline",
            translatedText: "离线",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        try controller.memoryLibrary.saveOrThrow([item])

        XCTAssertEqual(bootstrapAttempts, 2)
        XCTAssertEqual(controller.persistenceStatus, .coreDataAvailable(syncMode: .localOnly))
        XCTAssertEqual(controller.syncStatus, .localOnlyFallback(reason: "Core Data store unavailable"))
        XCTAssertTrue(controller.syncStatus.message.contains("Core Data store unavailable"))
        XCTAssertFalse(controller.syncStatus.message.contains("没有可用的 CloudKit entitlement"))
        XCTAssertEqual(try controller.memoryLibrary.loadOrThrow(), [item])
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

    func testSettingsImportRecordsLocalDataChange() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true, syncMode: .localOnly)
        let controller = AppDataController(coreDataStore: coreDataStore)
        let expectation = expectation(description: "settings import records local data change")
        let cancellable = controller.dataChangeMonitor.$revision.dropFirst().sink { revision in
            XCTAssertEqual(revision, 1)
            expectation.fulfill()
        }
        let item = MemoryItem(sourceText: "imported", translatedText: "已导入", sourceLanguage: .en, targetLanguage: .zh)
        let data = try MemoryImportExportService().exportData(items: [item])

        _ = try controller.settingsImportExport.importMemory(from: data)

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    func testNetworkStatusExplainsOfflineLocalAvailability() {
        let status = AppNetworkStatus.unavailable

        XCTAssertEqual(status.title, "网络不可用")
        XCTAssertTrue(status.message.contains("本机收藏、搜索和删除仍可使用"))
    }

    func testNetworkStatusMonitorPublishesOfflineChanges() {
        let monitor = AppNetworkStatusMonitor(startsMonitoring: false)
        let expectation = expectation(description: "network monitor publishes offline status")
        let cancellable = monitor.$status.dropFirst().sink { status in
            XCTAssertEqual(status, .unavailable)
            expectation.fulfill()
        }

        monitor.record(pathStatus: .unsatisfied)

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }
}

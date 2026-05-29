import SwiftUI

struct AppDataController {
    nonisolated(unsafe) static let live = AppDataController()

    let memoryLibrary: MemoryLibraryRepository
    let translationHistory: TranslationHistoryRepository
    let settingsImportExport: SettingsImportExportController
    let localDocumentRecovery: LocalPersistenceRecoveryController
    let persistenceStatus: AppPersistenceStatus

    init(
        coreDataStoreFactory: (() throws -> CoreDataMemoryStore)? = nil,
        syncMode: CoreDataSyncMode = .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier),
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore()
    ) {
        let coreDataStore: CoreDataMemoryStore?
        do {
            coreDataStore = try (coreDataStoreFactory ?? { try CoreDataMemoryStore(syncMode: syncMode) })()
            persistenceStatus = .coreDataAvailable(syncMode: syncMode)
        } catch {
            coreDataStore = nil
            persistenceStatus = .legacyFallback(reason: Self.failureReason(for: error))
        }

        memoryLibrary = MemoryLibraryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyMemoryStore
        )
        translationHistory = TranslationHistoryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyHistoryStore
        )
        settingsImportExport = SettingsImportExportController(memoryStore: memoryLibrary)
        localDocumentRecovery = LocalPersistenceRecoveryController()
    }

    init(
        coreDataStore: CoreDataMemoryStore,
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore()
    ) {
        self.init(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .localOnly,
            legacyMemoryStore: legacyMemoryStore,
            legacyHistoryStore: legacyHistoryStore
        )
    }

    private static func failureReason(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(describing: error) : message
    }
}

enum AppPersistenceStatus: Equatable {
    case coreDataAvailable(syncMode: CoreDataSyncMode)
    case legacyFallback(reason: String)

    var title: String {
        switch self {
        case .coreDataAvailable(let syncMode):
            switch syncMode {
            case .cloudKit:
                return "Core Data + iCloud 已启用"
            case .localOnly:
                return "Core Data 已启用"
            }
        case .legacyFallback:
            return "兼容存储模式"
        }
    }

    var message: String {
        switch self {
        case .coreDataAvailable(let syncMode):
            switch syncMode {
            case .cloudKit(let containerIdentifier):
                return "本机数据写入 Core Data，并配置通过 \(containerIdentifier) 在 iCloud 私有空间同步。同步时间取决于系统状态和网络。"
            case .localOnly:
                return "本机数据正在写入主存储。"
            }
        case .legacyFallback(let reason):
            return "主存储初始化失败，当前使用兼容存储：\(reason)"
        }
    }

    var systemImage: String {
        switch self {
        case .coreDataAvailable(let syncMode):
            switch syncMode {
            case .cloudKit:
                return "icloud"
            case .localOnly:
                return "internaldrive"
            }
        case .legacyFallback:
            return "externaldrive.badge.exclamationmark"
        }
    }

    var isDegraded: Bool {
        if case .legacyFallback = self {
            return true
        }
        return false
    }
}

private struct AppDataControllerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = AppDataController.live
}

extension EnvironmentValues {
    var appDataController: AppDataController {
        get { self[AppDataControllerKey.self] }
        set { self[AppDataControllerKey.self] = newValue }
    }
}

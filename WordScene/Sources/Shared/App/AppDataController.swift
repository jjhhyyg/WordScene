import SwiftUI

struct AppDataController {
    nonisolated(unsafe) static let live = AppDataController()

    let memoryLibrary: MemoryLibraryRepository
    let translationHistory: TranslationHistoryRepository
    let settingsImportExport: SettingsImportExportController
    let localDocumentRecovery: LocalPersistenceRecoveryController
    let persistenceStatus: AppPersistenceStatus
    let syncStatus: AppSyncStatus

    init(
        coreDataStoreFactory: (() throws -> CoreDataMemoryStore)? = nil,
        syncMode: CoreDataSyncMode = .defaultForCurrentProcess(),
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore()
    ) {
        let coreDataStore: CoreDataMemoryStore?
        do {
            coreDataStore = try (coreDataStoreFactory ?? { try CoreDataMemoryStore(syncMode: syncMode) })()
            persistenceStatus = .coreDataAvailable(syncMode: syncMode)
            syncStatus = AppSyncStatus(syncMode: syncMode)
        } catch {
            let reason = Self.failureReason(for: error)
            coreDataStore = nil
            persistenceStatus = .legacyFallback(reason: reason)
            syncStatus = .unavailable(reason: reason)
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
        case .coreDataAvailable:
            return "Core Data 已启用"
        case .legacyFallback:
            return "兼容存储模式"
        }
    }

    var message: String {
        switch self {
        case .coreDataAvailable:
            return "本机数据正在写入主存储。"
        case .legacyFallback(let reason):
            return "主存储初始化失败，当前使用兼容存储：\(reason)"
        }
    }

    var systemImage: String {
        switch self {
        case .coreDataAvailable:
            return "internaldrive"
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

enum AppSyncStatus: Equatable {
    case cloudKitConfigured(containerIdentifier: String)
    case localOnly
    case unavailable(reason: String)

    init(syncMode: CoreDataSyncMode) {
        switch syncMode {
        case .cloudKit(let containerIdentifier):
            self = .cloudKitConfigured(containerIdentifier: containerIdentifier)
        case .localOnly:
            self = .localOnly
        }
    }

    var title: String {
        switch self {
        case .cloudKitConfigured:
            return "iCloud 同步已配置"
        case .localOnly:
            return "仅本机存储"
        case .unavailable:
            return "同步不可用"
        }
    }

    var message: String {
        switch self {
        case .cloudKitConfigured(let containerIdentifier):
            return "已配置通过 \(containerIdentifier) 写入 iCloud 私有数据库。同步不是实时承诺，具体时间取决于系统、网络和 Apple ID 状态。"
        case .localOnly:
            return "当前进程没有可用的 CloudKit entitlement，数据仍可本机使用，但不会通过 iCloud 同步。"
        case .unavailable(let reason):
            return "主存储初始化失败，当前无法使用 iCloud 同步：\(reason)"
        }
    }

    var systemImage: String {
        switch self {
        case .cloudKitConfigured:
            return "icloud"
        case .localOnly:
            return "internaldrive"
        case .unavailable:
            return "icloud.slash"
        }
    }

    var tint: Color {
        switch self {
        case .cloudKitConfigured:
            return .secondary
        case .localOnly:
            return .orange
        case .unavailable:
            return .red
        }
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

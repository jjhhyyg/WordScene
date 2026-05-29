import SwiftUI

struct AppDataController {
    nonisolated(unsafe) static let live = AppDataController()

    let memoryLibrary: MemoryLibraryRepository
    let translationHistory: TranslationHistoryRepository
    let settingsImportExport: SettingsImportExportController
    let localDocumentRecovery: LocalPersistenceRecoveryController
    let persistenceStatus: AppPersistenceStatus

    init(
        coreDataStoreFactory: () throws -> CoreDataMemoryStore = { try CoreDataMemoryStore() },
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore()
    ) {
        let coreDataStore: CoreDataMemoryStore?
        do {
            coreDataStore = try coreDataStoreFactory()
            persistenceStatus = .coreDataAvailable
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
    case coreDataAvailable
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

private struct AppDataControllerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = AppDataController.live
}

extension EnvironmentValues {
    var appDataController: AppDataController {
        get { self[AppDataControllerKey.self] }
        set { self[AppDataControllerKey.self] = newValue }
    }
}

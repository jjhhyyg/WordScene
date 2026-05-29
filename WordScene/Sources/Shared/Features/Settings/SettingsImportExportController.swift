import Foundation

struct SettingsImportExportController {
    private let memoryStore: any MemoryLibraryDataStore
    private let importExportService: MemoryImportExportService
    private let changeRecorder: () -> Void

    init(
        memoryStore: any MemoryLibraryDataStore = MemoryLibraryRepository(),
        importExportService: MemoryImportExportService = MemoryImportExportService(),
        changeRecorder: @escaping () -> Void = {}
    ) {
        self.memoryStore = memoryStore
        self.importExportService = importExportService
        self.changeRecorder = changeRecorder
    }

    func prepareExport() throws -> SettingsMemoryExport {
        let items = try memoryStore.loadOrThrow()
        return SettingsMemoryExport(
            data: try importExportService.exportData(items: items),
            fileName: importExportService.exportFileName(),
            itemCount: items.count,
            privacyNotice: Self.exportPrivacyNotice
        )
    }

    func importMemory(
        from data: Data,
        conflictPolicy: SettingsMemoryImportConflictPolicy = .replaceExisting
    ) throws -> SettingsMemoryImportSummary {
        let result = try importExportService.importItems(
            from: data,
            existingItems: try memoryStore.loadOrThrow(),
            conflictStrategy: conflictPolicy.conflictStrategy
        )
        try memoryStore.saveOrThrow(result.items)
        changeRecorder()

        return SettingsMemoryImportSummary(
            importedCount: result.importedCount,
            replacedCount: result.replacedCount,
            skippedCount: result.skippedCount,
            totalCount: result.items.count
        )
    }

    private static let exportPrivacyNotice = "导出文件不加密，包含收藏内容，但不包含 API Token。请妥善保管。"
}

struct SettingsMemoryExport: Equatable {
    let data: Data
    let fileName: String
    let itemCount: Int
    let privacyNotice: String
}

struct SettingsMemoryImportSummary: Equatable {
    let importedCount: Int
    let replacedCount: Int
    let skippedCount: Int
    let totalCount: Int
}

enum SettingsMemoryImportConflictPolicy: String, CaseIterable, Identifiable {
    case replaceExisting
    case keepExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replaceExisting:
            return "覆盖重复项"
        case .keepExisting:
            return "保留现有项"
        }
    }

    var conflictStrategy: MemoryImportConflictStrategy {
        switch self {
        case .replaceExisting:
            return .replaceDuplicates
        case .keepExisting:
            return .skipDuplicates
        }
    }
}

import Foundation

struct SettingsImportExportController {
    private let memoryStore: any MemoryLibraryDataStore
    private let importExportService: MemoryImportExportService

    init(
        memoryStore: any MemoryLibraryDataStore = MemoryLibraryRepository(),
        importExportService: MemoryImportExportService = MemoryImportExportService()
    ) {
        self.memoryStore = memoryStore
        self.importExportService = importExportService
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
        conflictStrategy: MemoryImportConflictStrategy = .replaceDuplicates
    ) throws -> SettingsMemoryImportSummary {
        let result = try importExportService.importItems(
            from: data,
            existingItems: try memoryStore.loadOrThrow(),
            conflictStrategy: conflictStrategy
        )
        try memoryStore.saveOrThrow(result.items)

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

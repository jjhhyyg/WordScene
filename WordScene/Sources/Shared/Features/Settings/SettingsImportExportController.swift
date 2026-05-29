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
        let items = memoryStore.load()
        return SettingsMemoryExport(
            data: try importExportService.exportData(items: items),
            fileName: importExportService.exportFileName(),
            itemCount: items.count
        )
    }

    func importMemory(
        from data: Data,
        conflictStrategy: MemoryImportConflictStrategy = .replaceDuplicates
    ) throws -> SettingsMemoryImportSummary {
        let result = try importExportService.importItems(
            from: data,
            existingItems: memoryStore.load(),
            conflictStrategy: conflictStrategy
        )
        memoryStore.save(result.items)

        return SettingsMemoryImportSummary(
            importedCount: result.importedCount,
            replacedCount: result.replacedCount,
            skippedCount: result.skippedCount,
            totalCount: result.items.count
        )
    }
}

struct SettingsMemoryExport: Equatable {
    let data: Data
    let fileName: String
    let itemCount: Int
}

struct SettingsMemoryImportSummary: Equatable {
    let importedCount: Int
    let replacedCount: Int
    let skippedCount: Int
    let totalCount: Int
}

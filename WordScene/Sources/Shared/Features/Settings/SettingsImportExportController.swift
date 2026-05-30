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
            deletionTombstones: try (memoryStore as? any MemoryLibraryDeletionTombstoneProviding)?.loadDeletionTombstones() ?? [],
            conflictStrategy: conflictPolicy.conflictStrategy
        )
        if result.importedCount > 0 || result.replacedCount > 0 {
            try memoryStore.saveOrThrow(result.items)
            changeRecorder()
        }

        return SettingsMemoryImportSummary(
            importedCount: result.importedCount,
            replacedCount: result.replacedCount,
            skippedCount: result.skippedCount,
            totalCount: result.items.count
        )
    }

    private static var exportPrivacyNotice: String {
        String(localized: "导出文件不加密，包含收藏内容，但不包含 API Token。请妥善保管。", comment: "Privacy note shown before exporting saved memory.")
    }
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

    var statusMessage: String {
        if importedCount == 0 && replacedCount == 0 && skippedCount > 0 {
            let format = String(localized: "未导入新内容，已跳过 %lld 条重复项。", comment: "Import summary when all selected memory items were duplicates. The placeholder is the skipped count.")
            return String(format: format, Int64(skippedCount))
        }

        let format = String(localized: "已导入 %lld 条，覆盖 %lld 条，跳过 %lld 条。", comment: "Import summary. Placeholders are imported count, replaced count, and skipped count.")
        return String(format: format, Int64(importedCount), Int64(replacedCount), Int64(skippedCount))
    }
}

enum SettingsMemoryImportConflictPolicy: String, CaseIterable, Identifiable {
    case replaceExisting
    case keepExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replaceExisting:
            return String(localized: "覆盖重复项", comment: "Import conflict policy that replaces duplicate saved memory items.")
        case .keepExisting:
            return String(localized: "保留现有项", comment: "Import conflict policy that keeps existing saved memory items.")
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

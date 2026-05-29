import CryptoKit
import Foundation

struct MemoryImportExportService {
    static let schemaVersion = "2.0"

    private let now: () -> Date
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let appVersion: String
    private let appBuild: String
    private let platform: String

    init(
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
        appBuild: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
        platform: String = MemoryImportExportService.currentPlatform
    ) {
        self.now = now
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.platform = platform
    }

    func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd"

        return "memory-book-export-\(formatter.string(from: now())).json"
    }

    func exportData(items: [MemoryItem]) throws -> Data {
        let payload = MemoryExportPayload(
            exportSchemaVersion: Self.schemaVersion,
            appVersion: appVersion,
            exportedAt: now(),
            sourceDevice: MemoryExportSourceDevice(platform: platform, appBuild: appBuild),
            capabilities: MemoryExportCapabilities(
                containsRawResponses: false,
                containsDeletedItems: false
            ),
            items: items
        )
        let checksum = try checksum(for: payload)
        let document = MemoryExportDocument(payload: payload, checksum: checksum)

        return try encoder.encode(document)
    }

    func importItems(
        from data: Data,
        existingItems: [MemoryItem],
        conflictStrategy: MemoryImportConflictStrategy = .replaceDuplicates
    ) throws -> MemoryImportResult {
        let document: MemoryExportDocument
        do {
            document = try decoder.decode(MemoryExportDocument.self, from: data)
        } catch {
            throw MemoryImportExportError.invalidJSON
        }

        guard document.payload.exportSchemaVersion == Self.schemaVersion else {
            throw MemoryImportExportError.unsupportedSchemaVersion(document.payload.exportSchemaVersion)
        }

        guard try checksum(for: document.payload) == document.checksum else {
            throw MemoryImportExportError.checksumMismatch
        }

        return merge(
            importedItems: document.payload.items,
            into: existingItems,
            conflictStrategy: conflictStrategy
        )
    }

    private func merge(
        importedItems: [MemoryItem],
        into existingItems: [MemoryItem],
        conflictStrategy: MemoryImportConflictStrategy
    ) -> MemoryImportResult {
        var mergedItems = existingItems
        var importedCount = 0
        var replacedCount = 0
        var skippedCount = 0

        for importedItem in importedItems {
            let importedKey = MemoryImportKey(item: importedItem)
            if let duplicateIndex = mergedItems.firstIndex(where: { MemoryImportKey(item: $0) == importedKey }) {
                switch conflictStrategy {
                case .replaceDuplicates:
                    mergedItems[duplicateIndex] = importedItem
                    importedCount += 1
                    replacedCount += 1
                case .skipDuplicates:
                    skippedCount += 1
                }
            } else {
                mergedItems.insert(importedItem, at: 0)
                importedCount += 1
            }
        }

        return MemoryImportResult(
            items: mergedItems,
            importedCount: importedCount,
            replacedCount: replacedCount,
            skippedCount: skippedCount
        )
    }

    private func checksum(for payload: MemoryExportPayload) throws -> String {
        let payloadData = try encoder.encode(payload)
        let digest = SHA256.hash(data: payloadData)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    private static var currentPlatform: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "Apple"
        #endif
    }
}

enum MemoryImportConflictStrategy {
    case replaceDuplicates
    case skipDuplicates
}

struct MemoryImportResult: Equatable {
    let items: [MemoryItem]
    let importedCount: Int
    let replacedCount: Int
    let skippedCount: Int
}

enum MemoryImportExportError: Error, Equatable {
    case invalidJSON
    case unsupportedSchemaVersion(String)
    case checksumMismatch
}

private struct MemoryExportDocument: Codable {
    let payload: MemoryExportPayload
    let checksum: String

    init(payload: MemoryExportPayload, checksum: String) {
        self.payload = payload
        self.checksum = checksum
    }

    private enum CodingKeys: String, CodingKey {
        case checksum
        case exportSchemaVersion = "export_schema_version"
        case appVersion = "app_version"
        case exportedAt = "exported_at"
        case sourceDevice = "source_device"
        case capabilities
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.payload = MemoryExportPayload(
            exportSchemaVersion: try container.decode(String.self, forKey: .exportSchemaVersion),
            appVersion: try container.decode(String.self, forKey: .appVersion),
            exportedAt: try container.decode(Date.self, forKey: .exportedAt),
            sourceDevice: try container.decode(MemoryExportSourceDevice.self, forKey: .sourceDevice),
            capabilities: try container.decode(MemoryExportCapabilities.self, forKey: .capabilities),
            items: try container.decode([MemoryItem].self, forKey: .items)
        )
        self.checksum = try container.decode(String.self, forKey: .checksum)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload.exportSchemaVersion, forKey: .exportSchemaVersion)
        try container.encode(payload.appVersion, forKey: .appVersion)
        try container.encode(payload.exportedAt, forKey: .exportedAt)
        try container.encode(payload.sourceDevice, forKey: .sourceDevice)
        try container.encode(payload.capabilities, forKey: .capabilities)
        try container.encode(payload.items, forKey: .items)
        try container.encode(checksum, forKey: .checksum)
    }
}

private struct MemoryExportPayload: Codable {
    let exportSchemaVersion: String
    let appVersion: String
    let exportedAt: Date
    let sourceDevice: MemoryExportSourceDevice
    let capabilities: MemoryExportCapabilities
    let items: [MemoryItem]

    private enum CodingKeys: String, CodingKey {
        case exportSchemaVersion = "export_schema_version"
        case appVersion = "app_version"
        case exportedAt = "exported_at"
        case sourceDevice = "source_device"
        case capabilities
        case items
    }
}

private struct MemoryExportSourceDevice: Codable {
    let platform: String
    let appBuild: String

    private enum CodingKeys: String, CodingKey {
        case platform
        case appBuild = "app_build"
    }
}

private struct MemoryExportCapabilities: Codable {
    let containsRawResponses: Bool
    let containsDeletedItems: Bool

    private enum CodingKeys: String, CodingKey {
        case containsRawResponses = "contains_raw_responses"
        case containsDeletedItems = "contains_deleted_items"
    }
}

private struct MemoryImportKey: Equatable {
    let sourceText: String
    let translatedText: String
    let sourceLanguage: LanguageSelection
    let targetLanguage: LanguageSelection

    init(item: MemoryItem) {
        self.sourceText = Self.normalized(item.sourceText)
        self.translatedText = Self.normalized(item.translatedText)
        self.sourceLanguage = item.sourceLanguage
        self.targetLanguage = item.targetLanguage
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

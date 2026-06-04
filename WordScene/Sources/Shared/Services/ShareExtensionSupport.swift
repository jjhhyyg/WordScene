import Foundation

enum ShareExtensionConfiguration {
    static let appGroupIdentifier = "group.com.erikssonhou.leximemory"
    static let urlScheme = "wordscene"
    static let handoffHost = "share-translation"
}

struct ShareExtensionHandoffRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let sourceLanguage: LanguageSelection
    let targetLanguage: LanguageSelection
    let isFavoritePending: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: LanguageSelection,
        targetLanguage: LanguageSelection,
        isFavoritePending: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.isFavoritePending = isFavoritePending
        self.createdAt = Self.iso8601StableDate(createdAt)
    }

    var translationRecord: TranslationRecord {
        TranslationRecord(
            id: id,
            sourceText: sourceText,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            createdAt: createdAt
        )
    }

    private static func iso8601StableDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }
}

enum ShareExtensionPendingOperation: Codable, Equatable {
    case history(ShareExtensionHandoffRecord)
    case favorite(ShareExtensionHandoffRecord)

    private enum CodingKeys: String, CodingKey {
        case kind
        case record
    }

    private enum Kind: String, Codable {
        case history
        case favorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let record = try container.decode(ShareExtensionHandoffRecord.self, forKey: .record)

        switch kind {
        case .history:
            self = .history(record)
        case .favorite:
            self = .favorite(record)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .history(let record):
            try container.encode(Kind.history, forKey: .kind)
            try container.encode(record, forKey: .record)
        case .favorite(let record):
            try container.encode(Kind.favorite, forKey: .kind)
            try container.encode(record, forKey: .record)
        }
    }
}

struct ShareExtensionHandoffStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init?() {
        guard let directoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareExtensionConfiguration.appGroupIdentifier
        ) else {
            return nil
        }

        self.init(directoryURL: directoryURL)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ record: ShareExtensionHandoffRecord) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(record)
        try data.write(to: handoffURL(for: record.id), options: .atomic)
    }

    func load(id: UUID) throws -> ShareExtensionHandoffRecord? {
        let url = handoffURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        return try decoder.decode(ShareExtensionHandoffRecord.self, from: data)
    }

    func delete(id: UUID) throws {
        let url = handoffURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }

        try fileManager.removeItem(at: url)
    }

    func appendPendingOperation(_ operation: ShareExtensionPendingOperation) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(operation)
        try data.write(to: pendingOperationURL(createdAt: Date(), id: UUID()), options: .atomic)
    }

    func consumePendingOperations() throws -> [ShareExtensionPendingOperation] {
        let fileURLs = try pendingOperationFileURLs()
        guard !fileURLs.isEmpty else { return [] }

        var operations: [ShareExtensionPendingOperation] = []
        for fileURL in fileURLs {
            defer {
                try? fileManager.removeItem(at: fileURL)
            }

            do {
                let data = try Data(contentsOf: fileURL)
                operations.append(try decoder.decode(ShareExtensionPendingOperation.self, from: data))
            } catch {
                continue
            }
        }
        return operations
    }

    private func handoffURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("share-handoff-\(id.uuidString).json", isDirectory: false)
    }

    private func pendingOperationURL(createdAt: Date, id: UUID) -> URL {
        let timestamp = UInt64(createdAt.timeIntervalSince1970 * 1_000_000_000)
        return directoryURL.appendingPathComponent(
            "share-pending-operation-\(String(format: "%020llu", timestamp))-\(id.uuidString).json",
            isDirectory: false
        )
    }

    private func pendingOperationFileURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { url in
            let fileName = url.lastPathComponent
            return fileName.hasPrefix("share-pending-operation-") && fileName.hasSuffix(".json")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

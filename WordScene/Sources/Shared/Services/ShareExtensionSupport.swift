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
        var operations = try loadPendingOperations()
        operations.append(operation)
        try savePendingOperations(operations)
    }

    func consumePendingOperations() throws -> [ShareExtensionPendingOperation] {
        let operations = try loadPendingOperations()
        guard !operations.isEmpty else { return [] }

        try fileManager.removeItem(at: pendingOperationsURL)
        return operations
    }

    private var pendingOperationsURL: URL {
        directoryURL.appendingPathComponent("share-pending-operations.json", isDirectory: false)
    }

    private func handoffURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("share-handoff-\(id.uuidString).json", isDirectory: false)
    }

    private func loadPendingOperations() throws -> [ShareExtensionPendingOperation] {
        let url = pendingOperationsURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        return try decoder.decode([ShareExtensionPendingOperation].self, from: data)
    }

    private func savePendingOperations(_ operations: [ShareExtensionPendingOperation]) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(operations)
        try data.write(to: pendingOperationsURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

import Foundation

struct LocalPersistenceRecoveryController {
    private let defaults: UserDefaults
    private let keys: [String]
    private let now: () -> Date
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(
        defaults: UserDefaults = .standard,
        keys: [String] = ["memoryLibrary", "translationHistory"],
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current
    ) {
        self.defaults = defaults
        self.keys = keys
        self.now = now
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func prepareBackup() throws -> LocalPersistenceBackup {
        let createdAt = now()
        let documents = localDocumentEntries()
        let document = LocalPersistenceBackupDocument(
            schemaVersion: 1,
            createdAt: createdAt,
            documents: documents
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return LocalPersistenceBackup(
            data: try encoder.encode(document),
            fileName: backupFileName(for: createdAt),
            documentCount: documents.count
        )
    }

    func localDocumentCount() -> Int {
        keys.filter { defaults.data(forKey: $0) != nil }.count
    }

    @discardableResult
    func resetLocalDocuments() -> Int {
        var resetCount = 0
        for key in keys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            resetCount += 1
        }
        return resetCount
    }

    private func backupFileName(for date: Date) -> String {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        let components = configuredCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        return String(format: "wordscene-local-backup-%04d%02d%02d-%02d%02d%02d.json", year, month, day, hour, minute, second)
    }

    private func localDocumentEntries() -> [LocalPersistenceBackupDocumentEntry] {
        keys.compactMap { key -> LocalPersistenceBackupDocumentEntry? in
            guard let data = defaults.data(forKey: key) else {
                return nil
            }
            return LocalPersistenceBackupDocumentEntry(key: key, dataBase64: data.base64EncodedString())
        }
    }
}

struct LocalPersistenceBackup: Equatable {
    let data: Data
    let fileName: String
    let documentCount: Int
}

private struct LocalPersistenceBackupDocument: Encodable {
    let schemaVersion: Int
    let createdAt: Date
    let documents: [LocalPersistenceBackupDocumentEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case documents
    }
}

private struct LocalPersistenceBackupDocumentEntry: Encodable {
    let key: String
    let dataBase64: String

    enum CodingKeys: String, CodingKey {
        case key
        case dataBase64 = "data_base64"
    }
}

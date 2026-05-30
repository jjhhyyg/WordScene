import CoreData
import Foundation
#if os(macOS)
import Security
#endif

protocol CoreDataMemoryDataStore {
    func upsert(_ item: MemoryItem) throws
    func loadActiveItems() throws -> [MemoryItem]
    func softDelete(id: UUID, deletedAt: Date) throws
}

protocol CoreDataTranslationHistoryDataStore {
    func loadHistoryRecords() throws -> [TranslationRecord]
    func replaceHistoryRecords(_ records: [TranslationRecord]) throws
}

extension CoreDataMemoryDataStore {
    func softDelete(id: UUID) throws {
        try softDelete(id: id, deletedAt: Date())
    }
}

struct CoreDataDeletionTombstone: Equatable {
    let itemID: UUID
    let deletedAt: Date
}

enum CoreDataSyncMode: Equatable {
    case localOnly
    case cloudKit(containerIdentifier: String)

    static func defaultForCurrentProcess(
        containerIdentifier: String = CoreDataMemoryStore.productionCloudKitContainerIdentifier,
        isCloudSyncEnabled: () -> Bool = { CloudKitSyncPreference.isEnabled() },
        entitlementValue: (String) -> Any? = ProcessEntitlementReader.value
    ) -> CoreDataSyncMode {
        guard isCloudSyncEnabled() else {
            return .localOnly
        }

        guard
            let services = entitlementValue("com.apple.developer.icloud-services") as? [String],
            services.contains("CloudKit") || services.contains("CloudKit-Anonymous"),
            let containers = entitlementValue("com.apple.developer.icloud-container-identifiers") as? [String],
            containers.contains(containerIdentifier)
        else {
            return .localOnly
        }

        return .cloudKit(containerIdentifier: containerIdentifier)
    }
}

enum CloudKitSyncPreference {
    static let isEnabledKey = "cloudKitSync.isEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: isEnabledKey)
    }
}

private enum ProcessEntitlementReader {
    static func value(for key: String) -> Any? {
#if os(macOS)
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault) else {
            return nil
        }

        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
#else
        #if targetEnvironment(simulator)
        // Simulator test hosts often run without signed iCloud entitlements;
        // keep them local-only instead of bootstrapping a CloudKit store that
        // the process cannot actually use.
        return nil
        #else
        // iOS devices do not expose SecTask entitlement reads to app code. The
        // app's CloudKit capability is defined by the signed target entitlements.
        switch key {
        case "com.apple.developer.icloud-services":
            return ["CloudKit"]
        case "com.apple.developer.icloud-container-identifiers":
            return [CoreDataMemoryStore.productionCloudKitContainerIdentifier]
        default:
            return nil
        }
        #endif
#endif
    }
}

struct CoreDataMemoryStore: CoreDataMemoryDataStore, CoreDataTranslationHistoryDataStore {
    private static let modelName = "WordSceneModel"
    private static let translationItemEntityName = "TranslationItem"
    private static let historyRecordEntityName = "TranslationHistoryRecord"
    private static let tombstoneEntityName = "DeletionTombstone"
    private static let schemaVersion = 1
    static let productionCloudKitContainerIdentifier = "iCloud.com.erikssonhou.leximemory"

    private let container: NSPersistentContainer

    init(
        inMemory: Bool = false,
        syncMode: CoreDataSyncMode = .defaultForCurrentProcess()
    ) throws {
        let resolvedSyncMode: CoreDataSyncMode = inMemory ? .localOnly : syncMode
        let model = Self.makeModel()
        switch resolvedSyncMode {
        case .cloudKit:
            container = NSPersistentCloudKitContainer(name: Self.modelName, managedObjectModel: model)
        case .localOnly:
            container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)
        }

        let storeURL: URL?
        if inMemory {
            storeURL = nil
        } else {
            let storeDirectory = try Self.storeDirectoryURL()
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
            storeURL = storeDirectory.appendingPathComponent("WordScene.sqlite")
        }
        let description = Self.makeStoreDescription(
            inMemory: inMemory,
            syncMode: resolvedSyncMode,
            storeURL: storeURL
        )
        container.persistentStoreDescriptions = [description]

        var persistentStoreError: Error?
        container.loadPersistentStores { _, error in
            persistentStoreError = error
        }

        if let persistentStoreError {
            throw persistentStoreError
        }

        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    static func makeStoreDescription(
        inMemory: Bool,
        syncMode: CoreDataSyncMode,
        storeURL: URL? = nil
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
        } else {
            description.url = storeURL
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false

        if !inMemory {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            if case .cloudKit(let containerIdentifier) = syncMode {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: containerIdentifier
                )
            }
        }

        return description
    }

    static func cloudKitModelValidationFailures() -> [String] {
        makeModel().entities.flatMap { entity in
            entity.properties.compactMap { property in
                guard let attribute = property as? NSAttributeDescription,
                      !attribute.isOptional,
                      attribute.defaultValue == nil else {
                    return nil
                }
                return "\(entity.name ?? "Unknown").\(attribute.name)"
            }
        }
    }

    func upsert(_ item: MemoryItem) throws {
        let context = container.viewContext
        let object = try fetchTranslationItem(id: item.id, in: context) ??
            fetchActiveTranslationItem(duplicateKey: Self.duplicateKey(for: item), in: context) ??
            Self.insertObject(
            entityName: Self.translationItemEntityName,
            in: context
        )

        object.setValue(item.id, forKey: "id")
        object.setValue(item.sourceText, forKey: "sourceText")
        object.setValue(item.translatedText, forKey: "translatedText")
        object.setValue(item.sourceLanguage.rawValue, forKey: "sourceLanguage")
        object.setValue(item.targetLanguage.rawValue, forKey: "targetLanguage")
        object.setValue(item.note, forKey: "note")
        object.setValue(item.createdAt, forKey: "createdAt")
        object.setValue(item.updatedAt, forKey: "updatedAt")
        object.setValue(false, forKey: "isDeleted")
        object.setValue(nil, forKey: "deletedAt")
        object.setValue(Self.schemaVersion, forKey: "schemaVersion")
        object.setValue(Self.duplicateKey(for: item), forKey: "duplicateKey")

        try saveIfNeeded(context)
    }

    func loadActiveItems() throws -> [MemoryItem] {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.translationItemEntityName)
        request.predicate = NSPredicate(format: "isDeleted == NO")
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "sourceText", ascending: true)
        ]

        return try context.fetch(request).map(Self.makeMemoryItem)
    }

    func softDelete(id: UUID, deletedAt: Date = Date()) throws {
        let context = container.viewContext

        if let object = try fetchTranslationItem(id: id, in: context) {
            object.setValue(true, forKey: "isDeleted")
            object.setValue(deletedAt, forKey: "deletedAt")
            object.setValue(deletedAt, forKey: "updatedAt")
        }

        let tombstone = try fetchTombstone(itemID: id, in: context) ?? Self.insertObject(
            entityName: Self.tombstoneEntityName,
            in: context
        )
        tombstone.setValue(UUID(), forKey: "id")
        tombstone.setValue(id, forKey: "itemID")
        tombstone.setValue(deletedAt, forKey: "deletedAt")

        try saveIfNeeded(context)
    }

    func loadDeletionTombstones() throws -> [CoreDataDeletionTombstone] {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.tombstoneEntityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "deletedAt", ascending: true)
        ]

        return try context.fetch(request).map { object in
            CoreDataDeletionTombstone(
                itemID: object.value(forKey: "itemID") as? UUID ?? UUID(),
                deletedAt: object.value(forKey: "deletedAt") as? Date ?? .distantPast
            )
        }
    }

    func replaceHistoryRecords(_ records: [TranslationRecord]) throws {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.historyRecordEntityName)
        for object in try context.fetch(request) {
            context.delete(object)
        }

        for record in records {
            let object = try Self.insertObject(
                entityName: Self.historyRecordEntityName,
                in: context
            )
            Self.setValues(for: record, on: object)
        }

        try saveIfNeeded(context)
    }

    func loadHistoryRecords() throws -> [TranslationRecord] {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.historyRecordEntityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "sourceText", ascending: true)
        ]

        return try context.fetch(request).map(Self.makeTranslationRecord)
    }

    private func fetchTranslationItem(id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.translationItemEntityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func fetchActiveTranslationItem(
        duplicateKey: String,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.translationItemEntityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "duplicateKey == %@ AND isDeleted == NO", duplicateKey)
        return try context.fetch(request).first
    }

    private func fetchTombstone(itemID: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.tombstoneEntityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "itemID == %@", itemID as CVarArg)
        return try context.fetch(request).first
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else {
            return
        }

        try context.save()
    }

    private static func insertObject(entityName: String, in context: NSManagedObjectContext) throws -> NSManagedObject {
        guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
            throw CoreDataMemoryStoreError.missingEntity(entityName)
        }

        return NSManagedObject(entity: entity, insertInto: context)
    }

    private static func makeMemoryItem(from object: NSManagedObject) -> MemoryItem {
        MemoryItem(
            id: object.value(forKey: "id") as? UUID ?? UUID(),
            sourceText: object.value(forKey: "sourceText") as? String ?? "",
            translatedText: object.value(forKey: "translatedText") as? String ?? "",
            sourceLanguage: LanguageSelection(rawValue: object.value(forKey: "sourceLanguage") as? String ?? "") ?? .auto,
            targetLanguage: LanguageSelection(rawValue: object.value(forKey: "targetLanguage") as? String ?? "") ?? .zh,
            note: object.value(forKey: "note") as? String ?? "",
            createdAt: object.value(forKey: "createdAt") as? Date ?? .distantPast,
            updatedAt: object.value(forKey: "updatedAt") as? Date ?? .distantPast
        )
    }

    private static func setValues(for record: TranslationRecord, on object: NSManagedObject) {
        object.setValue(record.id, forKey: "id")
        object.setValue(record.sourceText, forKey: "sourceText")
        object.setValue(record.translatedText, forKey: "translatedText")
        object.setValue(record.sourceLanguage.rawValue, forKey: "sourceLanguage")
        object.setValue(record.targetLanguage.rawValue, forKey: "targetLanguage")
        object.setValue(record.createdAt, forKey: "createdAt")
        object.setValue(schemaVersion, forKey: "schemaVersion")
    }

    private static func makeTranslationRecord(from object: NSManagedObject) -> TranslationRecord {
        TranslationRecord(
            id: object.value(forKey: "id") as? UUID ?? UUID(),
            sourceText: object.value(forKey: "sourceText") as? String ?? "",
            translatedText: object.value(forKey: "translatedText") as? String ?? "",
            sourceLanguage: LanguageSelection(rawValue: object.value(forKey: "sourceLanguage") as? String ?? "") ?? .auto,
            targetLanguage: LanguageSelection(rawValue: object.value(forKey: "targetLanguage") as? String ?? "") ?? .zh,
            createdAt: object.value(forKey: "createdAt") as? Date ?? .distantPast
        )
    }

    private static func duplicateKey(for item: MemoryItem) -> String {
        [
            normalized(item.sourceText),
            normalized(item.translatedText),
            item.sourceLanguage.rawValue,
            item.targetLanguage.rawValue
        ].joined(separator: "\u{1F}")
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func storeDirectoryURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportURL.appendingPathComponent("WordScene", isDirectory: true)
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let translationItem = NSEntityDescription()
        translationItem.name = translationItemEntityName
        translationItem.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        translationItem.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("sourceText", type: .stringAttributeType),
            attribute("translatedText", type: .stringAttributeType),
            attribute("sourceLanguage", type: .stringAttributeType),
            attribute("targetLanguage", type: .stringAttributeType),
            attribute("note", type: .stringAttributeType, defaultValue: ""),
            attribute("createdAt", type: .dateAttributeType),
            attribute("updatedAt", type: .dateAttributeType),
            attribute("isDeleted", type: .booleanAttributeType, defaultValue: false),
            attribute("deletedAt", type: .dateAttributeType, isOptional: true),
            attribute("schemaVersion", type: .integer64AttributeType, defaultValue: schemaVersion),
            attribute("duplicateKey", type: .stringAttributeType)
        ]

        let tombstone = NSEntityDescription()
        tombstone.name = tombstoneEntityName
        tombstone.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        tombstone.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("itemID", type: .UUIDAttributeType),
            attribute("deletedAt", type: .dateAttributeType)
        ]

        let historyRecord = NSEntityDescription()
        historyRecord.name = historyRecordEntityName
        historyRecord.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        historyRecord.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("sourceText", type: .stringAttributeType),
            attribute("translatedText", type: .stringAttributeType),
            attribute("sourceLanguage", type: .stringAttributeType),
            attribute("targetLanguage", type: .stringAttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("schemaVersion", type: .integer64AttributeType, defaultValue: schemaVersion)
        ]

        model.entities = [translationItem, historyRecord, tombstone]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        isOptional: Bool = true,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }
}

private enum CoreDataMemoryStoreError: LocalizedError {
    case missingEntity(String)

    var errorDescription: String? {
        switch self {
        case let .missingEntity(entityName):
            "Missing Core Data entity: \(entityName)"
        }
    }
}

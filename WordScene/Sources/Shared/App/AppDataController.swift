import CloudKit
import CoreData
import Network
import SwiftUI

struct AppDataController {
    nonisolated(unsafe) static let live = liveForProcess()

    let memoryLibrary: MemoryLibraryRepository
    let translationHistory: TranslationHistoryRepository
    let settingsImportExport: SettingsImportExportController
    let localDocumentRecovery: LocalPersistenceRecoveryController
    let persistenceStatus: AppPersistenceStatus
    let syncStatus: AppSyncStatus
    let syncEventMonitor: CloudKitSyncEventMonitor
    let dataChangeMonitor: AppDataChangeMonitor
    let networkStatusMonitor: AppNetworkStatusMonitor

    init(
        coreDataStoreFactory: (() throws -> CoreDataMemoryStore)? = nil,
        syncMode: CoreDataSyncMode = .defaultForCurrentProcess(),
        syncEventStore: CloudKitSyncEventStore = CloudKitSyncEventStore(),
        dataChangeNotificationCenter: NotificationCenter = .default,
        networkStatusMonitor: AppNetworkStatusMonitor? = nil,
        startsNetworkMonitoring: Bool = false,
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore(),
        localDocumentRecovery: LocalPersistenceRecoveryController = LocalPersistenceRecoveryController()
    ) {
        self.networkStatusMonitor = networkStatusMonitor ?? AppNetworkStatusMonitor(
            startsMonitoring: startsNetworkMonitoring
        )
        let coreDataStore: CoreDataMemoryStore?
        let makePrimaryCoreDataStore = coreDataStoreFactory ?? {
            try CoreDataMemoryStore(syncMode: syncMode)
        }
        do {
            coreDataStore = try makePrimaryCoreDataStore()
            persistenceStatus = .coreDataAvailable(syncMode: syncMode)
            syncStatus = AppSyncStatus(syncMode: syncMode)
            syncEventMonitor = CloudKitSyncEventMonitor(
                syncStatus: syncStatus,
                eventStore: syncEventStore
            )
            dataChangeMonitor = AppDataChangeMonitor(notificationCenter: dataChangeNotificationCenter)
        } catch {
            if case .cloudKit = syncMode {
                let makeLocalCoreDataStore = coreDataStoreFactory ?? {
                    try CoreDataMemoryStore(syncMode: .localOnly)
                }
                do {
                    coreDataStore = try makeLocalCoreDataStore()
                    persistenceStatus = .coreDataAvailable(syncMode: .localOnly)
                    syncStatus = .localOnlyFallback(reason: Self.failureReason(for: error))
                    syncEventMonitor = CloudKitSyncEventMonitor(
                        syncStatus: syncStatus,
                        eventStore: syncEventStore
                    )
                    dataChangeMonitor = AppDataChangeMonitor(notificationCenter: dataChangeNotificationCenter)
                } catch {
                    let reason = Self.failureReason(for: error)
                    coreDataStore = nil
                    persistenceStatus = .legacyFallback(reason: reason)
                    syncStatus = .unavailable(reason: reason)
                    syncEventMonitor = CloudKitSyncEventMonitor(
                        syncStatus: syncStatus,
                        eventStore: syncEventStore
                    )
                    dataChangeMonitor = AppDataChangeMonitor(notificationCenter: dataChangeNotificationCenter)
                }
            } else {
                let reason = Self.failureReason(for: error)
                coreDataStore = nil
                persistenceStatus = .legacyFallback(reason: reason)
                syncStatus = .unavailable(reason: reason)
                syncEventMonitor = CloudKitSyncEventMonitor(
                    syncStatus: syncStatus,
                    eventStore: syncEventStore
                )
                dataChangeMonitor = AppDataChangeMonitor(notificationCenter: dataChangeNotificationCenter)
            }
        }

        memoryLibrary = MemoryLibraryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyMemoryStore,
            changeRecorder: { [dataChangeMonitor] in
                dataChangeMonitor.recordLocalChange()
            }
        )
        translationHistory = TranslationHistoryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyHistoryStore,
            changeRecorder: { [dataChangeMonitor] in
                dataChangeMonitor.recordLocalChange()
            }
        )
        settingsImportExport = SettingsImportExportController(
            memoryStore: memoryLibrary
        )
        self.localDocumentRecovery = localDocumentRecovery
    }

    init(
        coreDataStore: CoreDataMemoryStore,
        syncEventStore: CloudKitSyncEventStore = CloudKitSyncEventStore(),
        dataChangeNotificationCenter: NotificationCenter = .default,
        networkStatusMonitor: AppNetworkStatusMonitor? = nil,
        startsNetworkMonitoring: Bool = false,
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore(),
        localDocumentRecovery: LocalPersistenceRecoveryController = LocalPersistenceRecoveryController()
    ) {
        self.init(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .localOnly,
            syncEventStore: syncEventStore,
            dataChangeNotificationCenter: dataChangeNotificationCenter,
            networkStatusMonitor: networkStatusMonitor,
            startsNetworkMonitoring: startsNetworkMonitoring,
            legacyMemoryStore: legacyMemoryStore,
            legacyHistoryStore: legacyHistoryStore,
            localDocumentRecovery: localDocumentRecovery
        )
    }

    private static func failureReason(for error: Error) -> String {
        AppErrorDescription.syncFailureReason(for: error)
    }

    static func liveForProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppDataController {
        guard arguments.contains("-WordSceneUITest") else {
            return AppDataController(startsNetworkMonitoring: true)
        }

        let suiteName = environment["WORDSCENE_UI_TEST_SUITE"] ?? "WordSceneUITests"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)

        let coreDataStore = try? CoreDataMemoryStore(inMemory: true)
        let legacyMemoryStore = MemoryLibraryStore(defaults: userDefaults)
        let legacyHistoryStore = TranslationHistoryStore(defaults: userDefaults)
        let syncEventStore = CloudKitSyncEventStore(userDefaults: userDefaults)
        let localDocumentRecovery = LocalPersistenceRecoveryController(defaults: userDefaults)

        if let coreDataStore {
            let controller = AppDataController(
                coreDataStore: coreDataStore,
                syncEventStore: syncEventStore,
                legacyMemoryStore: legacyMemoryStore,
                legacyHistoryStore: legacyHistoryStore,
                localDocumentRecovery: localDocumentRecovery
            )
            seedUITestDataIfNeeded(environment: environment, into: controller)
            return controller
        }

        let controller = AppDataController(
            coreDataStoreFactory: { throw CocoaError(.persistentStoreOpen) },
            syncMode: .localOnly,
            syncEventStore: syncEventStore,
            legacyMemoryStore: legacyMemoryStore,
            legacyHistoryStore: legacyHistoryStore,
            localDocumentRecovery: localDocumentRecovery
        )
        seedUITestDataIfNeeded(environment: environment, into: controller)
        return controller
    }

    private static func seedUITestDataIfNeeded(
        environment: [String: String],
        into controller: AppDataController
    ) {
        guard let seed = environment["WORDSCENE_UI_TEST_SEED"] else {
            return
        }

        if seed == "scroll-swipe-fixture" {
            seedScrollSwipeFixture(into: controller)
            return
        }

        guard seed == "library-search-fixture" else {
            return
        }

        let memoryItem = MemoryItem(
            sourceText: "seeded library phrase",
            translatedText: "种子收藏短语",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "seeded note",
            isStarred: true
        )
        let historyRecord = TranslationRecord(
            sourceText: "seeded history phrase",
            translatedText: "种子历史短语",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        try? controller.memoryLibrary.saveOrThrow([memoryItem])
        try? controller.translationHistory.saveOrThrow([historyRecord])
    }

    private static func seedScrollSwipeFixture(into controller: AppDataController) {
        let now = Date()
        var memoryItems: [MemoryItem] = []
        var historyRecords: [TranslationRecord] = []

        for index in 1...16 {
            let timestamp = now.addingTimeInterval(TimeInterval(-index))
            let itemNumber = String(format: "%02d", index)

            memoryItems.append(
                MemoryItem(
                    sourceText: "scroll library item \(itemNumber)",
                    translatedText: "滚动收藏条目 \(itemNumber)",
                    sourceLanguage: .en,
                    targetLanguage: .zh,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    isStarred: index == 1
                )
            )

            historyRecords.append(
                TranslationRecord(
                    sourceText: "scroll history item \(itemNumber)",
                    translatedText: "滚动历史条目 \(itemNumber)",
                    sourceLanguage: .en,
                    targetLanguage: .zh,
                    createdAt: timestamp
                )
            )
        }

        try? controller.memoryLibrary.saveOrThrow(memoryItems)
        try? controller.translationHistory.saveOrThrow(historyRecords)
    }
}

enum AppErrorDescription {
    private static let maximumReasonLength = 1_200

    static func syncFailureReason(for error: Error) -> String {
        var components: [String] = []
        var visitedErrors = Set<ObjectIdentifier>()
        append(error, label: nil, to: &components, visitedErrors: &visitedErrors)

        let reason = deduplicated(components)
            .joined(separator: "；")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reason.isEmpty else {
            return String(describing: error)
        }
        if reason.count <= maximumReasonLength {
            return reason
        }
        return String(reason.prefix(maximumReasonLength)) + "..."
    }

    private static func append(
        _ error: Error,
        label: String?,
        to components: inout [String],
        visitedErrors: inout Set<ObjectIdentifier>
    ) {
        let nsError = error as NSError
        let identifier = ObjectIdentifier(nsError)
        guard visitedErrors.insert(identifier).inserted else {
            return
        }

        let description = description(for: nsError)
        if let label {
            components.append("\(label)：\(description)")
        } else {
            components.append(description)
        }

        appendStringDetail(NSLocalizedFailureReasonErrorKey, prefix: String(localized: "失败原因", comment: "Diagnostic label for an error failure reason."), from: nsError, to: &components)
        appendStringDetail(NSLocalizedRecoverySuggestionErrorKey, prefix: String(localized: "恢复建议", comment: "Diagnostic label for an error recovery suggestion."), from: nsError, to: &components)
        appendPartialFailures(from: nsError, to: &components, visitedErrors: &visitedErrors)
        appendErrorList(NSDetailedErrorsKey, prefix: String(localized: "详细错误", comment: "Diagnostic label for detailed errors."), from: nsError, to: &components, visitedErrors: &visitedErrors)
        appendErrorList(NSMultipleUnderlyingErrorsKey, prefix: String(localized: "底层错误", comment: "Diagnostic label for underlying errors."), from: nsError, to: &components, visitedErrors: &visitedErrors)

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            append(underlying, label: String(localized: "底层错误", comment: "Diagnostic label for underlying errors."), to: &components, visitedErrors: &visitedErrors)
        }
    }

    private static func description(for error: NSError) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = "\(error.domain) code \(error.code)"
        guard !message.isEmpty else {
            return signature
        }
        guard shouldIncludeDiagnosticSignature(for: error) else {
            return message
        }
        if message.contains(signature) {
            return message
        }
        return "\(message) [\(signature)]"
    }

    private static func shouldIncludeDiagnosticSignature(for error: NSError) -> Bool {
        switch error.domain {
        case CKErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain:
            return true
        default:
            return false
        }
    }

    private static func appendStringDetail(
        _ key: String,
        prefix: String,
        from error: NSError,
        to components: inout [String]
    ) {
        guard let detail = error.userInfo[key] as? String else {
            return
        }
        let cleaned = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            components.append("\(prefix)：\(cleaned)")
        }
    }

    private static func appendPartialFailures(
        from error: NSError,
        to components: inout [String],
        visitedErrors: inout Set<ObjectIdentifier>
    ) {
        guard let partialFailures = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Any] else {
            return
        }

        for key in partialFailures.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
            guard let partialError = partialFailures[key] as? Error else {
                continue
            }
            append(
                partialError,
                label: String(
                    format: String(localized: "部分失败 %@", comment: "Diagnostic label for a partial failure. The placeholder is the failed item identifier."),
                    String(describing: key)
                ),
                to: &components,
                visitedErrors: &visitedErrors
            )
        }
    }

    private static func appendErrorList(
        _ key: String,
        prefix: String,
        from error: NSError,
        to components: inout [String],
        visitedErrors: inout Set<ObjectIdentifier>
    ) {
        guard let errors = error.userInfo[key] as? [Error] else {
            return
        }

        for (index, nestedError) in errors.enumerated() {
            append(nestedError, label: "\(prefix) \(index + 1)", to: &components, visitedErrors: &visitedErrors)
        }
    }

    private static func deduplicated(_ components: [String]) -> [String] {
        var seen = Set<String>()
        return components.filter { component in
            let cleaned = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                return false
            }
            return seen.insert(cleaned).inserted
        }
    }
}

enum AppPersistenceStatus: Equatable {
    case coreDataAvailable(syncMode: CoreDataSyncMode)
    case legacyFallback(reason: String)

    var title: String {
        switch self {
        case .coreDataAvailable:
            return String(localized: "Core Data 已启用", comment: "Persistence status title when Core Data is active.")
        case .legacyFallback:
            return String(localized: "兼容存储模式", comment: "Persistence status title when legacy storage fallback is active.")
        }
    }

    var message: String {
        switch self {
        case .coreDataAvailable:
            return String(localized: "本机数据正在写入主存储。", comment: "Persistence status message when local data is writing to the primary store.")
        case .legacyFallback(let reason):
            let format = String(localized: "主存储初始化失败，当前使用兼容存储：%@", comment: "Persistence status message when primary storage fails. The placeholder is the failure reason.")
            return String(format: format, reason)
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

enum AppSyncStatus: Equatable {
    case cloudKitConfigured(containerIdentifier: String)
    case localOnly
    case localOnlyFallback(reason: String)
    case unavailable(reason: String)

    init(syncMode: CoreDataSyncMode) {
        switch syncMode {
        case .cloudKit(let containerIdentifier):
            self = .cloudKitConfigured(containerIdentifier: containerIdentifier)
        case .localOnly:
            self = .localOnly
        }
    }

    var title: String {
        switch self {
        case .cloudKitConfigured:
            return String(localized: "iCloud 同步已配置", comment: "Sync status title when iCloud sync is configured.")
        case .localOnly, .localOnlyFallback:
            return String(localized: "仅本机存储", comment: "Sync status title when only local storage is active.")
        case .unavailable:
            return String(localized: "同步不可用", comment: "Sync status title when sync is unavailable.")
        }
    }

    var message: String {
        switch self {
        case .cloudKitConfigured(let containerIdentifier):
            let format = String(localized: "已配置通过 %@ 写入 iCloud 私有数据库。同步不是实时承诺，具体时间取决于系统、网络和 Apple ID 状态。", comment: "Sync status message when iCloud sync is configured. The placeholder is the CloudKit container identifier.")
            return String(format: format, containerIdentifier)
        case .localOnly:
            return String(localized: "当前进程没有可用的 CloudKit entitlement，数据仍可本机使用，但不会通过 iCloud 同步。", comment: "Sync status message when CloudKit entitlements are unavailable.")
        case .localOnlyFallback(let reason):
            let format = String(localized: "iCloud 同步存储初始化失败，已切换为仅本机存储。数据仍可本机使用，但不会通过 iCloud 同步：%@", comment: "Sync status message when iCloud storage fails and local fallback is used. The placeholder is the failure reason.")
            return String(format: format, reason)
        case .unavailable(let reason):
            let format = String(localized: "主存储初始化失败，当前无法使用 iCloud 同步：%@", comment: "Sync status message when sync is unavailable because storage failed. The placeholder is the failure reason.")
            return String(format: format, reason)
        }
    }

    var systemImage: String {
        switch self {
        case .cloudKitConfigured:
            return "icloud"
        case .localOnly, .localOnlyFallback:
            return "internaldrive"
        case .unavailable:
            return "icloud.slash"
        }
    }

    var tint: Color {
        switch self {
        case .cloudKitConfigured:
            return .secondary
        case .localOnly, .localOnlyFallback:
            return .orange
        case .unavailable:
            return .red
        }
    }
}

enum AppNetworkStatus: Equatable {
    case checking
    case available(isExpensive: Bool, isConstrained: Bool)
    case unavailable

    var title: String {
        switch self {
        case .checking:
            return String(localized: "网络状态检测中", comment: "Network status title while checking connectivity.")
        case .available:
            return String(localized: "网络可用", comment: "Network status title when network is available.")
        case .unavailable:
            return String(localized: "网络不可用", comment: "Network status title when network is unavailable.")
        }
    }

    var message: String {
        switch self {
        case .checking:
            return String(localized: "正在检测网络状态。本机收藏和搜索仍可使用。", comment: "Network status message while checking connectivity.")
        case .available(let isExpensive, let isConstrained):
            if isConstrained {
                return String(localized: "当前处于低数据模式，同步和翻译可能由系统延后。本机收藏和搜索不受影响。", comment: "Network status message for constrained low data mode.")
            }
            if isExpensive {
                return String(localized: "当前可能使用蜂窝或热点网络，同步和翻译可能产生流量。本机收藏和搜索不受影响。", comment: "Network status message for expensive network connections.")
            }
            return String(localized: "网络可用于翻译请求和 iCloud 同步。本机数据仍会先写入本地存储。", comment: "Network status message when normal network is available.")
        case .unavailable:
            return String(localized: "当前离线。翻译请求和 iCloud 同步会暂停，但本机收藏、搜索和删除仍可使用。", comment: "Network status message when offline.")
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "network"
        case .available:
            return "wifi"
        case .unavailable:
            return "wifi.slash"
        }
    }

    var tint: Color {
        switch self {
        case .checking:
            return .secondary
        case .available:
            return .secondary
        case .unavailable:
            return .orange
        }
    }
}

enum CloudSyncEventKind: String, Codable, Equatable {
    case setup
    case importFromCloud
    case exportToCloud

    var actionLabel: String {
        switch self {
        case .setup:
            return String(localized: "准备 iCloud 同步", comment: "Cloud sync event label for setup.")
        case .importFromCloud:
            return String(localized: "从 iCloud 导入", comment: "Cloud sync event label for importing from iCloud.")
        case .exportToCloud:
            return String(localized: "向 iCloud 上传", comment: "Cloud sync event label for uploading to iCloud.")
        }
    }
}

struct CloudSyncEvent: Codable, Equatable {
    let kind: CloudSyncEventKind
    let startDate: Date
    let endDate: Date?
    let succeeded: Bool
    let errorDescription: String?
}

enum AppSyncEventStatus: Equatable {
    case unavailable(String)
    case waitingForCloudEvents
    case inProgress(kind: CloudSyncEventKind, startDate: Date)
    case lastSuccess(kind: CloudSyncEventKind, completedAt: Date)
    case lastFailure(kind: CloudSyncEventKind, completedAt: Date, reason: String)

    init(syncStatus: AppSyncStatus) {
        switch syncStatus {
        case .cloudKitConfigured:
            self = .waitingForCloudEvents
        case .localOnly, .localOnlyFallback:
            self = .unavailable(String(localized: "当前为仅本机存储，不会收到 iCloud 同步事件。", comment: "Sync event status message when using local-only storage."))
        case .unavailable(let reason):
            self = .unavailable(String(format: String(localized: "同步不可用：%@", comment: "Sync event status message when sync is unavailable. The placeholder is the reason."), reason))
        }
    }

    mutating func record(_ event: CloudSyncEvent) {
        if event.succeeded, let endDate = event.endDate {
            self = .lastSuccess(kind: event.kind, completedAt: endDate)
        } else if let errorDescription = event.errorDescription {
            self = .lastFailure(
                kind: event.kind,
                completedAt: event.endDate ?? Date(),
                reason: errorDescription
            )
        } else {
            self = .inProgress(kind: event.kind, startDate: event.startDate)
        }
    }

    var title: String {
        switch self {
        case .unavailable:
            return String(localized: "没有同步事件", comment: "Sync event status title when there are no sync events.")
        case .waitingForCloudEvents:
            return String(localized: "等待 iCloud 同步事件", comment: "Sync event status title while waiting for iCloud events.")
        case .inProgress:
            return String(localized: "正在同步", comment: "Sync event status title while syncing.")
        case .lastSuccess:
            return String(localized: "最近同步成功", comment: "Sync event status title after recent successful sync.")
        case .lastFailure:
            return String(localized: "同步出现错误", comment: "Sync event status title after a sync error.")
        }
    }

    var message: String {
        switch self {
        case .unavailable(let reason):
            return reason
        case .waitingForCloudEvents:
            return String(localized: "还没有收到 iCloud 同步事件。完成签名设备测试前，这不能证明多端已同步。", comment: "Sync event status message before any iCloud events are observed.")
        case .inProgress(let kind, let startDate):
            let format = String(localized: "%@中，开始于 %@。", comment: "Sync event message while an event is in progress. Placeholders are the event label and start date.")
            return String(format: format, kind.actionLabel, Self.format(startDate))
        case .lastSuccess(let kind, let completedAt):
            let format = String(localized: "%@已完成：%@。", comment: "Sync event message after a successful event. Placeholders are the event label and completion date.")
            return String(format: format, kind.actionLabel, Self.format(completedAt))
        case .lastFailure(let kind, let completedAt, let reason):
            let format = String(localized: "%@失败：%@。%@", comment: "Sync event message after a failed event. Placeholders are the event label, completion date, and failure reason.")
            return String(format: format, kind.actionLabel, Self.format(completedAt), reason)
        }
    }

    var librarySyncBadgeText: String {
        switch self {
        case .inProgress:
            return String(localized: "正在同步", comment: "Short sync badge while syncing.")
        case .lastSuccess(kind: .exportToCloud, completedAt: _):
            return String(localized: "已同步云端", comment: "Short sync badge after cloud export succeeds.")
        case .lastFailure:
            return String(localized: "同步未完成", comment: "Short sync badge after sync failure.")
        default:
            return String(localized: "已保存", comment: "Short sync badge when data is saved locally.")
        }
    }

    var hasSuccessfulCloudExport: Bool {
        if case .lastSuccess(kind: .exportToCloud, completedAt: _) = self {
            return true
        }
        return false
    }

    var hasSuccessfulCloudImport: Bool {
        if case .lastSuccess(kind: .importFromCloud, completedAt: _) = self {
            return true
        }
        return false
    }

    var systemImage: String {
        switch self {
        case .unavailable:
            return "icloud.slash"
        case .waitingForCloudEvents:
            return "clock"
        case .inProgress:
            return "arrow.triangle.2.circlepath"
        case .lastSuccess:
            return "checkmark.icloud"
        case .lastFailure:
            return "exclamationmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .unavailable:
            return .secondary
        case .waitingForCloudEvents, .inProgress:
            return .orange
        case .lastSuccess:
            return .secondary
        case .lastFailure:
            return .red
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct CloudKitSyncEventStore {
    private static let storageKey = "cloudKitSyncEvent.latest"

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = Self.storageKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> CloudSyncEvent? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(CloudSyncEvent.self, from: data)
    }

    func save(_ event: CloudSyncEvent) {
        guard let data = try? JSONEncoder().encode(event) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}

// CloudKit event notifications are delivered on the main queue below.
final class CloudKitSyncEventMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var status: AppSyncEventStatus

    private var observer: NSObjectProtocol?
    private let notificationCenter: NotificationCenter
    private let eventStore: CloudKitSyncEventStore

    init(
        syncStatus: AppSyncStatus,
        eventStore: CloudKitSyncEventStore = CloudKitSyncEventStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        var initialStatus = AppSyncEventStatus(syncStatus: syncStatus)
        if case .cloudKitConfigured = syncStatus, let latestEvent = eventStore.load() {
            initialStatus.record(latestEvent)
        }
        status = initialStatus
        self.notificationCenter = notificationCenter
        self.eventStore = eventStore

        if case .cloudKitConfigured = syncStatus {
            observer = notificationCenter.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = Self.event(from: notification) else {
                    return
                }
                self?.record(event)
            }
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func record(_ event: CloudSyncEvent) {
        eventStore.save(event)
        status.record(event)
    }

    private static func event(from notification: Notification) -> CloudSyncEvent? {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return nil
        }

        return CloudSyncEvent(
            kind: kind(for: event.type),
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded,
            errorDescription: event.error.map(AppErrorDescription.syncFailureReason(for:))
        )
    }

    private static func kind(for type: NSPersistentCloudKitContainer.EventType) -> CloudSyncEventKind {
        switch type {
        case .setup:
            return .setup
        case .import:
            return .importFromCloud
        case .export:
            return .exportToCloud
        @unknown default:
            return .setup
        }
    }
}

final class AppDataChangeMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var revision = 0

    private var observer: NSObjectProtocol?
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordExternalChange()
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func recordExternalChange() {
        recordLocalChange()
    }

    func recordLocalChange() {
        revision &+= 1
    }
}

final class AppNetworkStatusMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var status: AppNetworkStatus

    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.erikssonhou.wordscene.network-status")

    init(
        initialStatus: AppNetworkStatus = .checking,
        startsMonitoring: Bool = false
    ) {
        status = initialStatus

        guard startsMonitoring else {
            monitor = nil
            return
        }

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.record(path)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor?.cancel()
    }

    func record(_ path: NWPath) {
        record(
            pathStatus: path.status,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    func record(
        pathStatus: NWPath.Status,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        let nextStatus: AppNetworkStatus
        switch pathStatus {
        case .satisfied:
            nextStatus = .available(isExpensive: isExpensive, isConstrained: isConstrained)
        case .unsatisfied, .requiresConnection:
            nextStatus = .unavailable
        @unknown default:
            nextStatus = .checking
        }

        DispatchQueue.main.async { [weak self] in
            self?.status = nextStatus
        }
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

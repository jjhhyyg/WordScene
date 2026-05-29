import CoreData
import Network
import SwiftUI

struct AppDataController {
    nonisolated(unsafe) static let live = AppDataController(startsNetworkMonitoring: true)

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
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore()
    ) {
        self.networkStatusMonitor = networkStatusMonitor ?? AppNetworkStatusMonitor(
            startsMonitoring: startsNetworkMonitoring
        )
        let coreDataStore: CoreDataMemoryStore?
        do {
            coreDataStore = try (coreDataStoreFactory ?? { try CoreDataMemoryStore(syncMode: syncMode) })()
            persistenceStatus = .coreDataAvailable(syncMode: syncMode)
            syncStatus = AppSyncStatus(syncMode: syncMode)
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

        memoryLibrary = MemoryLibraryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyMemoryStore
        )
        translationHistory = TranslationHistoryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyHistoryStore
        )
        settingsImportExport = SettingsImportExportController(
            memoryStore: memoryLibrary,
            changeRecorder: { [dataChangeMonitor] in
                dataChangeMonitor.recordLocalChange()
            }
        )
        localDocumentRecovery = LocalPersistenceRecoveryController()
    }

    init(
        coreDataStore: CoreDataMemoryStore,
        syncEventStore: CloudKitSyncEventStore = CloudKitSyncEventStore(),
        dataChangeNotificationCenter: NotificationCenter = .default,
        networkStatusMonitor: AppNetworkStatusMonitor? = nil,
        startsNetworkMonitoring: Bool = false,
        legacyMemoryStore: MemoryLibraryStore = MemoryLibraryStore(),
        legacyHistoryStore: TranslationHistoryStore = TranslationHistoryStore()
    ) {
        self.init(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .localOnly,
            syncEventStore: syncEventStore,
            dataChangeNotificationCenter: dataChangeNotificationCenter,
            networkStatusMonitor: networkStatusMonitor,
            startsNetworkMonitoring: startsNetworkMonitoring,
            legacyMemoryStore: legacyMemoryStore,
            legacyHistoryStore: legacyHistoryStore
        )
    }

    private static func failureReason(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(describing: error) : message
    }
}

enum AppPersistenceStatus: Equatable {
    case coreDataAvailable(syncMode: CoreDataSyncMode)
    case legacyFallback(reason: String)

    var title: String {
        switch self {
        case .coreDataAvailable:
            return "Core Data 已启用"
        case .legacyFallback:
            return "兼容存储模式"
        }
    }

    var message: String {
        switch self {
        case .coreDataAvailable:
            return "本机数据正在写入主存储。"
        case .legacyFallback(let reason):
            return "主存储初始化失败，当前使用兼容存储：\(reason)"
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
            return "iCloud 同步已配置"
        case .localOnly:
            return "仅本机存储"
        case .unavailable:
            return "同步不可用"
        }
    }

    var message: String {
        switch self {
        case .cloudKitConfigured(let containerIdentifier):
            return "已配置通过 \(containerIdentifier) 写入 iCloud 私有数据库。同步不是实时承诺，具体时间取决于系统、网络和 Apple ID 状态。"
        case .localOnly:
            return "当前进程没有可用的 CloudKit entitlement，数据仍可本机使用，但不会通过 iCloud 同步。"
        case .unavailable(let reason):
            return "主存储初始化失败，当前无法使用 iCloud 同步：\(reason)"
        }
    }

    var systemImage: String {
        switch self {
        case .cloudKitConfigured:
            return "icloud"
        case .localOnly:
            return "internaldrive"
        case .unavailable:
            return "icloud.slash"
        }
    }

    var tint: Color {
        switch self {
        case .cloudKitConfigured:
            return .secondary
        case .localOnly:
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
            return "网络状态检测中"
        case .available:
            return "网络可用"
        case .unavailable:
            return "网络不可用"
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "正在检测网络状态。本机收藏和搜索仍可使用。"
        case .available(let isExpensive, let isConstrained):
            if isConstrained {
                return "当前处于低数据模式，同步和翻译可能由系统延后。本机收藏和搜索不受影响。"
            }
            if isExpensive {
                return "当前可能使用蜂窝或热点网络，同步和翻译可能产生流量。本机收藏和搜索不受影响。"
            }
            return "网络可用于翻译请求和 iCloud 同步。本机数据仍会先写入本地存储。"
        case .unavailable:
            return "当前离线。翻译请求和 iCloud 同步会暂停，但本机收藏、搜索和删除仍可使用。"
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
            return "准备 iCloud 同步"
        case .importFromCloud:
            return "从 iCloud 导入"
        case .exportToCloud:
            return "向 iCloud 上传"
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
        case .localOnly:
            self = .unavailable("当前为仅本机存储，不会收到 iCloud 同步事件。")
        case .unavailable(let reason):
            self = .unavailable("同步不可用：\(reason)")
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
            return "没有同步事件"
        case .waitingForCloudEvents:
            return "等待 iCloud 同步事件"
        case .inProgress:
            return "正在同步"
        case .lastSuccess:
            return "最近同步成功"
        case .lastFailure:
            return "同步出现错误"
        }
    }

    var message: String {
        switch self {
        case .unavailable(let reason):
            return reason
        case .waitingForCloudEvents:
            return "还没有收到 iCloud 同步事件。完成签名设备测试前，这不能证明多端已同步。"
        case .inProgress(let kind, let startDate):
            return "\(kind.actionLabel)中，开始于 \(Self.format(startDate))。"
        case .lastSuccess(let kind, let completedAt):
            return "\(kind.actionLabel)已完成：\(Self.format(completedAt))。"
        case .lastFailure(let kind, let completedAt, let reason):
            return "\(kind.actionLabel)失败：\(Self.format(completedAt))。\(reason)"
        }
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
            errorDescription: event.error?.localizedDescription
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

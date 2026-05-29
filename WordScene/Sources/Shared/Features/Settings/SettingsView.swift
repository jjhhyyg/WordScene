import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @AppStorage("allowsAnonymousCrashReports") private var allowsAnonymousCrashReports = false
    @State private var apiToken = ""
    @State private var tokenStatus: SettingsTokenStatus = .idle
    @State private var importExportStatus: SettingsImportExportStatus = .idle
    @State private var exportDocument = MemoryExportFileDocument()
    @State private var exportFileName = "memory-book-export.json"
    @State private var isExportingMemory = false
    @State private var isImportingMemory = false
    @State private var recoveryStatus: SettingsLocalRecoveryStatus = .idle
    @State private var recoveryBackupDocument = MemoryExportFileDocument()
    @State private var recoveryBackupFileName = "wordscene-local-backup.json"
    @State private var isExportingRecoveryBackup = false
    @State private var isConfirmingLegacyReset = false
    @Environment(\.appDataController) private var dataController
    @Environment(\.adaptiveLayout) private var adaptiveLayout

    private let credentialStore = KeychainCredentialStore()
    private let balanceClient = DeepSeekBalanceClient()
    private var importExportController: SettingsImportExportController {
        dataController.settingsImportExport
    }
    private var recoveryController: LocalPersistenceRecoveryController {
        dataController.localDocumentRecovery
    }

    var body: some View {
        Group {
        #if os(macOS)
            macSettingsBody
        #else
            mobileSettingsBody
        #endif
        }
        .fileExporter(
            isPresented: $isExportingMemory,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFileName
        ) { result in
            handleExportCompletion(result)
        }
        .fileExporter(
            isPresented: $isExportingRecoveryBackup,
            document: recoveryBackupDocument,
            contentType: .json,
            defaultFilename: recoveryBackupFileName
        ) { result in
            handleRecoveryBackupCompletion(result)
        }
        .fileImporter(
            isPresented: $isImportingMemory,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .confirmationDialog(
            "重置旧缓存？",
            isPresented: $isConfirmingLegacyReset,
            titleVisibility: .visible
        ) {
            Button("重置旧缓存", role: .destructive) {
                resetLegacyDocuments()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除早期本机记忆和翻译历史缓存。建议先导出原始备份。")
        }
    }

    private var mobileSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showsSettingsHeader {
                    settingsHeader
                }

                if usesTwoColumnSettings {
                    LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                        deepSeekCard
                        persistenceStatusCard
                        privacyCard
                        importExportCard
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        deepSeekCard
                        persistenceStatusCard
                        privacyCard
                        importExportCard
                    }
                }
            }
            .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, settingsHorizontalPadding)
            .padding(.vertical, settingsVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsBackground.ignoresSafeArea())
        .navigationTitle("设置")
        .onAppear {
            loadSavedToken()
        }
    }

    #if os(macOS)
    private var macSettingsBody: some View {
        Form {
            Section("DeepSeek") {
                settingValueRow("模型", value: "deepseek-v4-flash")
                settingValueRow("Base URL", value: "https://api.deepseek.com")

                SecureField("sk-...", text: $apiToken)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("DeepSeek API Token")

                tokenStatusView
                deepSeekTokenButtons
            }

            Section("隐私") {
                Toggle("匿名崩溃日志", isOn: $allowsAnonymousCrashReports)
                    .accessibilityLabel("允许发送匿名崩溃日志")

                Text("默认关闭，不包含 Token、原文、译文或导出文件。敏感内容仅保存在本机设置和系统凭据存储中。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("数据存储") {
                persistenceStatusView
                syncStatusView
                NetworkStatusView(monitor: dataController.networkStatusMonitor)
                SyncEventStatusView(monitor: dataController.syncEventMonitor)
                recoveryStatusView

                HStack {
                    Spacer()
                    localRecoveryButtons
                }
            }

            Section("导入导出") {
                settingValueRow("导出文件名", value: "memory-book-export-YYYYMMDD.json")
                settingValueRow("范围", value: "全量导入 / 全量导出")
                importExportStatusView

                HStack {
                    Spacer()
                    Button {
                        presentImport()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .disabled(importExportStatus.isWorking)

                    Button {
                        prepareExport()
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .disabled(importExportStatus.isWorking)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .frame(minWidth: 620, minHeight: 500)
        .background(settingsBackground)
        .navigationTitle("设置")
        .onAppear {
            loadSavedToken()
        }
    }
    #endif

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.largeTitle.bold())

            Text("管理模型连接、隐私和数据迁移。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        #if os(macOS)
        .padding(.top, 4)
        #endif
    }

    private var deepSeekCard: some View {
        SettingsCard(title: "DeepSeek", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                settingValueRow("模型", value: "deepseek-v4-flash")
                settingValueRow("Base URL", value: "https://api.deepseek.com")

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("sk-...", text: $apiToken)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DeepSeek API Token")
                }

                tokenStatusView
                deepSeekTokenButtons
            }
        }
    }

    private var tokenStatusView: some View {
        Label(tokenStatus.message, systemImage: tokenStatus.systemImage)
            .font(.footnote)
            .foregroundStyle(tokenStatus.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importExportStatusView: some View {
        Label(importExportStatus.message, systemImage: importExportStatus.systemImage)
            .font(.footnote)
            .foregroundStyle(importExportStatus.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recoveryStatusView: some View {
        Label(recoveryStatus.message, systemImage: recoveryStatus.systemImage)
            .font(.footnote)
            .foregroundStyle(recoveryStatus.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deepSeekTokenButtons: some View {
        HStack(spacing: 10) {
            Button {
                saveToken()
            } label: {
                Label("保存", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(trimmedToken.isEmpty || tokenStatus.isWorking)
            .accessibilityLabel("保存 DeepSeek Token")

            Button {
                Task {
                    await testToken()
                }
            } label: {
                Label("测试连接", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedToken.isEmpty || tokenStatus.isWorking)
            .accessibilityLabel("测试 DeepSeek Token")

            Button(role: .destructive) {
                deleteToken()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 34)
            }
            .buttonStyle(.bordered)
            .disabled(tokenStatus.isWorking)
            .accessibilityLabel("删除 DeepSeek Token")
        }
        .controlSize(.large)
    }

    private var privacyCard: some View {
        SettingsCard(title: "隐私", systemImage: "hand.raised") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $allowsAnonymousCrashReports) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("匿名崩溃日志")
                        Text("默认关闭，不包含 Token、原文、译文或导出文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("允许发送匿名崩溃日志")

                Label("敏感内容仅保存在本机设置和系统凭据存储中。", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var persistenceStatusCard: some View {
        SettingsCard(title: "数据存储", systemImage: "internaldrive") {
            VStack(alignment: .leading, spacing: 14) {
                persistenceStatusView
                syncStatusView
                NetworkStatusView(monitor: dataController.networkStatusMonitor)
                SyncEventStatusView(monitor: dataController.syncEventMonitor)

                Divider()

                recoveryStatusView
                localRecoveryButtons
            }
        }
    }

    private var persistenceStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(dataController.persistenceStatus.title, systemImage: dataController.persistenceStatus.systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(persistenceStatusTint)

            Text(dataController.persistenceStatus.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(dataController.syncStatus.title, systemImage: dataController.syncStatus.systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(dataController.syncStatus.tint)

            Text(dataController.syncStatus.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importExportCard: some View {
        SettingsCard(title: "导入导出", systemImage: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: 14) {
                settingValueRow("导出文件名", value: "memory-book-export-YYYYMMDD.json")
                settingValueRow("范围", value: "全量导入 / 全量导出")
                importExportStatusView

                HStack(spacing: 10) {
                    Button {
                        presentImport()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(importExportStatus.isWorking)

                    Button {
                        prepareExport()
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(importExportStatus.isWorking)
                }
                .controlSize(.large)
            }
        }
    }

    private var localRecoveryButtons: some View {
        HStack(spacing: 10) {
            Button {
                prepareLocalBackup()
            } label: {
                Label("导出原始备份", systemImage: "externaldrive.badge.timemachine")
            }
            .buttonStyle(.bordered)
            .disabled(recoveryStatus.isWorking)

            Button(role: .destructive) {
                isConfirmingLegacyReset = true
            } label: {
                Label("重置旧缓存", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(recoveryStatus.isWorking)
        }
        .controlSize(.large)
    }

    private func settingValueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.callout)
                .multilineTextAlignment(.trailing)
        }
    }

    private var usesTwoColumnSettings: Bool {
        #if os(macOS)
        return true
        #else
        return adaptiveLayout.usesContentColumns
        #endif
    }

    private var showsSettingsHeader: Bool {
        #if os(macOS)
        return true
        #else
        return !adaptiveLayout.usesTabNavigation
        #endif
    }

    private var settingsColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 280), spacing: 18, alignment: .top),
            GridItem(.flexible(minimum: 280), spacing: 18, alignment: .top)
        ]
    }

    private var settingsContentMaxWidth: CGFloat {
        #if os(macOS)
        return 920
        #else
        return adaptiveLayout.usesCompactContent ? .infinity : (usesTwoColumnSettings ? 920 : 680)
        #endif
    }

    private var settingsHorizontalPadding: CGFloat {
        #if os(macOS)
        return 28
        #else
        return adaptiveLayout.pageHorizontalPadding
        #endif
    }

    private var settingsVerticalPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 18
        #endif
    }

    private var settingsBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }

    private var persistenceStatusTint: Color {
        dataController.persistenceStatus.isDegraded ? .orange : .secondary
    }

    private var trimmedToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadSavedToken() {
        do {
            apiToken = try credentialStore.read(account: DeepSeekCredential.tokenAccount) ?? ""
            tokenStatus = apiToken.isEmpty ? .idle : .saved
        } catch {
            tokenStatus = .failed(settingsErrorMessage(for: error))
        }
    }

    @MainActor
    private func saveToken() {
        do {
            try credentialStore.save(trimmedToken, account: DeepSeekCredential.tokenAccount)
            tokenStatus = .saved
        } catch {
            tokenStatus = .failed(settingsErrorMessage(for: error))
        }
    }

    @MainActor
    private func deleteToken() {
        do {
            try credentialStore.delete(account: DeepSeekCredential.tokenAccount)
            apiToken = ""
            tokenStatus = .idle
        } catch {
            tokenStatus = .failed(settingsErrorMessage(for: error))
        }
    }

    @MainActor
    private func testToken() async {
        tokenStatus = .testing
        do {
            _ = try await balanceClient.fetchBalance(apiToken: trimmedToken)
            try credentialStore.save(trimmedToken, account: DeepSeekCredential.tokenAccount)
            tokenStatus = .valid
        } catch {
            tokenStatus = .failed(settingsErrorMessage(for: error))
        }
    }

    @MainActor
    private func prepareExport() {
        importExportStatus = .working("正在准备导出文件...")

        do {
            let export = try importExportController.prepareExport()
            exportDocument = MemoryExportFileDocument(data: export.data)
            exportFileName = export.fileName
            importExportStatus = .working("准备导出 \(export.itemCount) 条记忆。\(export.privacyNotice)")
            isExportingMemory = true
        } catch {
            importExportStatus = .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func handleExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            importExportStatus = .success("导出文件已生成。导出文件不加密，包含收藏内容，但不包含 API Token。请妥善保管。")
        case .failure(let error):
            importExportStatus = isUserCancelled(error) ? .idle : .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func prepareLocalBackup() {
        recoveryStatus = .working("正在准备旧缓存原始备份...")

        do {
            let backup = try recoveryController.prepareBackup()
            recoveryBackupDocument = MemoryExportFileDocument(data: backup.data)
            recoveryBackupFileName = backup.fileName
            recoveryStatus = .working("准备导出 \(backup.documentCount) 个旧缓存文档。")
            isExportingRecoveryBackup = true
        } catch {
            recoveryStatus = .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func handleRecoveryBackupCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            recoveryStatus = .success("旧缓存原始备份已生成。")
        case .failure(let error):
            recoveryStatus = isUserCancelled(error) ? .idle : .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func resetLegacyDocuments() {
        let resetCount = recoveryController.resetLocalDocuments()
        recoveryStatus = .success("已重置 \(resetCount) 个旧缓存文档。")
    }

    @MainActor
    private func presentImport() {
        importExportStatus = .working("请选择要导入的 JSON 文件。")
        isImportingMemory = true
    }

    @MainActor
    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importExportStatus = .idle
                return
            }
            importMemory(from: url)
        case .failure(let error):
            importExportStatus = isUserCancelled(error) ? .idle : .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func importMemory(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let summary = try importExportController.importMemory(from: data)
            importExportStatus = .success(
                "已导入 \(summary.importedCount) 条，覆盖 \(summary.replacedCount) 条，跳过 \(summary.skippedCount) 条。"
            )
        } catch {
            importExportStatus = .failed(importExportErrorMessage(for: error))
        }
    }

    private func settingsErrorMessage(for error: Error) -> String {
        if let balanceError = error as? DeepSeekBalanceError {
            switch balanceError {
            case .invalidResponse:
                return "DeepSeek 返回无效响应。"
            case .unavailableBalance:
                return "Token 可认证，但账户余额不可用。请检查 DeepSeek 余额。"
            case .unauthorized:
                return "Token 无效或已过期。"
            case .httpStatus(let status):
                return "DeepSeek 请求失败：HTTP \(status)。"
            }
        }

        if let keychainError = error as? KeychainCredentialError {
            switch keychainError {
            case .unhandledStatus(let status):
                return "系统凭据存储失败：\(status)。"
            }
        }

        return "操作失败，请稍后重试。"
    }

    private func importExportErrorMessage(for error: Error) -> String {
        if let importExportError = error as? MemoryImportExportError {
            switch importExportError {
            case .invalidJSON:
                return "导入文件不是有效的 WordScene JSON。"
            case .unsupportedSchemaVersion:
                return "导入文件版本不支持，请升级 App 后重试。"
            case .checksumMismatch:
                return "导入文件校验失败，文件可能已被修改或损坏。"
            }
        }

        return error.localizedDescription.isEmpty ? "导入导出失败，请稍后重试。" : error.localizedDescription
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

private struct SyncEventStatusView: View {
    @ObservedObject var monitor: CloudKitSyncEventMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(monitor.status.title, systemImage: monitor.status.systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(monitor.status.tint)

            Text(monitor.status.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NetworkStatusView: View {
    @ObservedObject var monitor: AppNetworkStatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(monitor.status.title, systemImage: monitor.status.systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(monitor.status.tint)

            Text(monitor.status.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SettingsTokenStatus: Equatable {
    case idle
    case saved
    case testing
    case valid
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "Token 只会保存在本机系统凭据存储中。"
        case .saved:
            return "Token 已保存在本机。"
        case .testing:
            return "正在测试 DeepSeek 连接..."
        case .valid:
            return "连接成功，Token 已保存。"
        case .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "lock"
        case .saved:
            return "key.fill"
        case .testing:
            return "arrow.triangle.2.circlepath"
        case .valid:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle, .saved:
            return .secondary
        case .testing:
            return .accentColor
        case .valid:
            return .green
        case .failed:
            return .red
        }
    }

    var isWorking: Bool {
        self == .testing
    }
}

private enum SettingsImportExportStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "导出文件不加密，包含收藏内容，但不包含 API Token。请妥善保管。"
        case .working(let message), .success(let message), .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "lock.doc"
        case .working:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .working:
            return .accentColor
        case .success:
            return .green
        case .failed:
            return .red
        }
    }

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }
}

private enum SettingsLocalRecoveryStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "旧缓存维护只处理早期本机文档，可先导出原始备份再重置。"
        case .working(let message), .success(let message), .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "wrench.and.screwdriver"
        case .working:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .working:
            return .accentColor
        case .success:
            return .green
        case .failed:
            return .red
        }
    }

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }
}

private struct MemoryExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.7)
        }
        #else
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        #endif
    }
}

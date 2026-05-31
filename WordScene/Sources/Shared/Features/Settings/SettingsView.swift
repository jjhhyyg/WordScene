import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @AppStorage(CloudKitSyncPreference.isEnabledKey) private var isCloudKitSyncRequested = false
    @State private var apiToken = ""
    @State private var tokenStatus: SettingsTokenStatus = .idle
    @State private var importExportStatus: SettingsImportExportStatus = .idle
    @State private var importConflictPolicy: SettingsMemoryImportConflictPolicy = .replaceExisting
    @State private var exportDocument = MemoryExportFileDocument()
    @State private var exportFileName = "memory-book-export.json"
    @State private var isExportingMemory = false
    #if os(iOS)
    @State private var documentExportRequest: SettingsDocumentExportRequest?
    #endif
    @State private var isImportingMemory = false
    @State private var recoveryStatus: SettingsLocalRecoveryStatus = .idle
    @State private var recoveryBackupDocument = MemoryExportFileDocument()
    @State private var recoveryBackupFileName = "wordscene-local-backup.json"
    @State private var isExportingRecoveryBackup = false
    @State private var isConfirmingLegacyReset = false
    @State private var isConfirmingDeepSeekTokenDeletion = false
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
        #if os(iOS)
        .sheet(item: $documentExportRequest) { request in
            SettingsDocumentExporter(fileURL: request.fileURL) { result in
                completeDocumentExport(request, result: result)
            }
        }
        #endif
        .alert(
            String(localized: "删除 DeepSeek Token？", comment: "Alert title before deleting the saved DeepSeek token."),
            isPresented: $isConfirmingDeepSeekTokenDeletion
        ) {
            Button(String(localized: "取消", comment: "Cancel button title."), role: .cancel) {}
            Button(String(localized: "删除", comment: "Delete action title."), role: .destructive) {
                confirmDeepSeekTokenDeletion()
            }
        } message: {
            Text(String(localized: "删除后这台设备上的翻译 Token 会被移除，之后需要重新保存 Token 才能继续翻译。", comment: "Alert message before deleting the saved DeepSeek token."))
        }
        .confirmationDialog(
            String(localized: "重置旧缓存？", comment: "Confirmation title before resetting legacy local cache documents."),
            isPresented: $isConfirmingLegacyReset,
            titleVisibility: .visible
        ) {
            Button(String(localized: "重置旧缓存", comment: "Destructive button title for resetting legacy local cache documents."), role: .destructive) {
                resetLegacyDocuments()
            }
            Button(String(localized: "取消", comment: "Cancel button title."), role: .cancel) {}
        } message: {
            Text(String(localized: "这会删除早期本机记忆和翻译历史缓存。建议先导出原始备份。", comment: "Warning shown before resetting legacy local cache documents."))
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
                        importExportCard
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        deepSeekCard
                        persistenceStatusCard
                        importExportCard
                    }
                }
            }
            .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, settingsHorizontalPadding)
            .padding(.top, settingsTopPadding)
            .padding(.bottom, settingsBottomPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "设置", comment: "Navigation title for settings."))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            loadSavedToken()
        }
    }

    #if os(macOS)
    private var macSettingsBody: some View {
        Form {
            Section(String(localized: "翻译服务", comment: "Settings section title for translation service setup.")) {
                SecureField("sk-...", text: $apiToken)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("DeepSeek API Token")
                    .accessibilityIdentifier("settings.deepSeek.token")

                tokenStatusView
                deepSeekTokenButtons
            }

            Section(String(localized: "同步", comment: "Settings section title for sync controls.")) {
                iCloudSyncPreferenceToggle
                userFacingSyncStatusView
                if dataController.persistenceStatus.isDegraded {
                    persistenceStatusView
                }
                if shouldShowNetworkStatus {
                    NetworkStatusView(monitor: dataController.networkStatusMonitor)
                }
                if shouldShowSyncEventStatus {
                    SyncEventStatusView(monitor: dataController.syncEventMonitor)
                }
                if showsLegacyRecoveryTools {
                    recoveryStatusView

                    HStack {
                        Spacer()
                        localRecoveryButtons
                    }
                }
            }

            Section(String(localized: "导入导出", comment: "Settings section title for import and export.")) {
                Picker(String(localized: "重复项", comment: "Picker label for duplicate import handling."), selection: $importConflictPolicy) {
                    ForEach(SettingsMemoryImportConflictPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                importExportStatusView

                HStack {
                    Spacer()
                    Button {
                        presentImport()
                    } label: {
                        Label(String(localized: "导入", comment: "Button title for importing saved memory."), systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("settings.import.button")
                    .disabled(importExportStatus.isWorking)

                    Button {
                        prepareExport()
                    } label: {
                        Label(String(localized: "导出", comment: "Button title for exporting saved memory."), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.export.button")
                    .disabled(importExportStatus.isWorking)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .frame(minWidth: 620, minHeight: 500)
        .background(settingsBackground)
        .navigationTitle(String(localized: "设置", comment: "Navigation title for settings."))
        .onAppear {
            loadSavedToken()
        }
    }
    #endif

    private var settingsHeader: some View {
        Text(String(localized: "设置", comment: "Large title for settings."))
            .font(.largeTitle.bold())
            .accessibilityIdentifier("settings.title")
        #if os(macOS)
        .padding(.top, 4)
        #endif
    }

    private var deepSeekCard: some View {
        SettingsCard(title: String(localized: "翻译服务", comment: "Settings card title for translation service setup."), systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("sk-...", text: $apiToken)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DeepSeek API Token")
                        .accessibilityIdentifier("settings.deepSeek.token")
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
            .accessibilityIdentifier("settings.importExport.status")
    }

    private var recoveryStatusView: some View {
        Label(recoveryStatus.message, systemImage: recoveryStatus.systemImage)
            .font(.footnote)
            .foregroundStyle(recoveryStatus.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var deepSeekTokenButtons: some View {
        #if os(iOS)
        if adaptiveLayout.usesCompactContent {
            compactDeepSeekTokenButtons
        } else {
            horizontalDeepSeekTokenButtons
        }
        #else
        horizontalDeepSeekTokenButtons
        #endif
    }

    private var horizontalDeepSeekTokenButtons: some View {
        HStack(spacing: 10) {
            saveDeepSeekTokenButton
            testDeepSeekTokenButton
            deleteDeepSeekTokenButton(includeTitle: false)
        }
        .controlSize(.large)
    }

    private var compactDeepSeekTokenButtons: some View {
        VStack(spacing: 10) {
            testDeepSeekTokenButton

            HStack(spacing: 10) {
                saveDeepSeekTokenButton
                deleteDeepSeekTokenButton(includeTitle: true)
            }
        }
        .controlSize(.large)
    }

    private var saveDeepSeekTokenButton: some View {
        Button {
            saveToken()
        } label: {
            Label(String(localized: "保存", comment: "Save button title."), systemImage: "key")
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(trimmedToken.isEmpty || tokenStatus.isWorking)
        .accessibilityLabel(String(localized: "保存 DeepSeek Token", comment: "Accessibility label for saving the DeepSeek token."))
        .accessibilityIdentifier("settings.deepSeek.save")
    }

    private var testDeepSeekTokenButton: some View {
        Button {
            Task {
                await testToken()
            }
        } label: {
            Label(String(localized: "测试连接", comment: "Button title for testing the DeepSeek token."), systemImage: "checkmark.seal")
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(trimmedToken.isEmpty || tokenStatus.isWorking)
        .accessibilityLabel(String(localized: "测试 DeepSeek Token", comment: "Accessibility label for testing the DeepSeek token."))
        .accessibilityIdentifier("settings.deepSeek.test")
    }

    @ViewBuilder
    private func deleteDeepSeekTokenButton(includeTitle: Bool) -> some View {
        Button(role: .destructive) {
            isConfirmingDeepSeekTokenDeletion = true
        } label: {
            if includeTitle {
                Label(String(localized: "删除", comment: "Delete action title."), systemImage: "trash")
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity)
            } else {
                Image(systemName: "trash")
                    .frame(width: 34)
            }
        }
        .buttonStyle(.bordered)
        .disabled(tokenStatus.isWorking)
        .accessibilityLabel(String(localized: "删除 DeepSeek Token", comment: "Accessibility label for deleting the DeepSeek token."))
        .accessibilityIdentifier("settings.deepSeek.delete")
    }

    private var persistenceStatusCard: some View {
        SettingsCard(title: String(localized: "同步", comment: "Settings card title for sync controls."), systemImage: "icloud") {
            VStack(alignment: .leading, spacing: 14) {
                iCloudSyncPreferenceToggle
                userFacingSyncStatusView
                if dataController.persistenceStatus.isDegraded {
                    persistenceStatusView
                }
                if shouldShowNetworkStatus {
                    NetworkStatusView(monitor: dataController.networkStatusMonitor)
                }
                if shouldShowSyncEventStatus {
                    SyncEventStatusView(monitor: dataController.syncEventMonitor)
                }

                if showsLegacyRecoveryTools {
                    Divider()

                    recoveryStatusView
                    localRecoveryButtons
                }
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

    private var iCloudSyncPreferenceToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isCloudKitSyncRequested) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "使用 iCloud 同步", comment: "Toggle title for enabling iCloud sync."))
                    Text(iCloudSyncPreferenceMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel(String(localized: "使用 iCloud 同步", comment: "Accessibility label for enabling iCloud sync."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iCloudSyncPreferenceMessage: String {
        if isCloudKitSyncRequested == isCloudKitSyncActive {
            return isCloudKitSyncActive
                ? String(localized: "收藏和历史会在登录同一 Apple ID 的设备间同步。", comment: "Settings message when iCloud sync is active.")
                : String(localized: "收藏和历史只保存在这台设备。", comment: "Settings message when local-only storage is active.")
        }

        return String(localized: "重启 App 后生效，已有内容不会被删除。", comment: "Settings message after changing the iCloud sync preference.")
    }

    private var isCloudKitSyncActive: Bool {
        if case .cloudKitConfigured = dataController.syncStatus {
            return true
        }
        return false
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

    private var userFacingSyncStatusView: some View {
        Label(userFacingSyncStatusMessage, systemImage: dataController.syncStatus.systemImage)
            .font(.footnote)
            .foregroundStyle(dataController.syncStatus.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var userFacingSyncStatusMessage: String {
        switch dataController.syncStatus {
        case .cloudKitConfigured:
            return String(localized: "iCloud 同步已开启。", comment: "Short user-facing sync status when iCloud sync is active.")
        case .localOnly:
            return String(localized: "当前只保存在本机。", comment: "Short user-facing sync status when local-only storage is active.")
        case .localOnlyFallback, .unavailable:
            return dataController.syncStatus.message
        }
    }

    private var importExportCard: some View {
        SettingsCard(title: String(localized: "导入导出", comment: "Settings card title for import and export."), systemImage: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "重复项", comment: "Picker label for duplicate import handling."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(String(localized: "重复项", comment: "Picker label for duplicate import handling."), selection: $importConflictPolicy) {
                        ForEach(SettingsMemoryImportConflictPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                importExportStatusView

                HStack(spacing: 10) {
                    Button {
                        presentImport()
                    } label: {
                        Label(String(localized: "导入", comment: "Button title for importing saved memory."), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.import.button")
                    .disabled(importExportStatus.isWorking)

                    Button {
                        prepareExport()
                    } label: {
                        Label(String(localized: "导出", comment: "Button title for exporting saved memory."), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.export.button")
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
                Label(String(localized: "导出原始备份", comment: "Button title for exporting a raw legacy local cache backup."), systemImage: "externaldrive.badge.timemachine")
            }
            .buttonStyle(.bordered)
            .disabled(recoveryStatus.isWorking)

            Button(role: .destructive) {
                isConfirmingLegacyReset = true
            } label: {
                Label(String(localized: "重置旧缓存", comment: "Button title for resetting legacy local cache documents."), systemImage: "trash")
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
        return true
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

    private var settingsTopPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 8
        #endif
    }

    private var settingsBottomPadding: CGFloat {
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

    private var shouldShowNetworkStatus: Bool {
        switch dataController.networkStatusMonitor.status {
        case .available(isExpensive: false, isConstrained: false):
            return false
        case .checking, .available, .unavailable:
            return true
        }
    }

    private var shouldShowSyncEventStatus: Bool {
        switch dataController.syncEventMonitor.status {
        case .inProgress, .lastFailure:
            return true
        case .unavailable, .waitingForCloudEvents, .lastSuccess:
            return false
        }
    }

    private var showsLegacyRecoveryTools: Bool {
        recoveryController.localDocumentCount() > 0 || recoveryStatus != .idle
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
    private func confirmDeepSeekTokenDeletion() {
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
        importExportStatus = .working(String(localized: "正在准备导出文件...", comment: "Status shown while preparing a memory export file."))

        do {
            let export = try importExportController.prepareExport()
            exportDocument = MemoryExportFileDocument(data: export.data)
            exportFileName = export.fileName
            let format = String(localized: "已准备 %lld 条记忆，请在系统面板中选择保存位置。%@", comment: "Status shown after preparing a memory export. The first placeholder is the exported item count; the second is the privacy notice.")
            importExportStatus = .notice(String(format: format, Int64(export.itemCount), export.privacyNotice))
            #if os(iOS)
            documentExportRequest = try makeDocumentExportRequest(
                kind: .memory,
                fileName: export.fileName,
                data: export.data
            )
            #else
            isExportingMemory = true
            #endif
        } catch {
            importExportStatus = .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func handleExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let format = String(localized: "已导出 %@。%@", comment: "Status shown after exporting memory. The first placeholder is the file name; the second is the privacy notice.")
            importExportStatus = .success(String(format: format, url.lastPathComponent, SettingsImportExportStatus.privacyNotice))
        case .failure(let error):
            importExportStatus = isUserCancelled(error) ? .notice(String(localized: "已取消导出，未写入文件。", comment: "Status shown when the user cancels memory export.")) : .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func prepareLocalBackup() {
        recoveryStatus = .working(String(localized: "正在准备旧缓存原始备份...", comment: "Status shown while preparing a legacy local cache backup."))

        do {
            guard recoveryController.localDocumentCount() > 0 else {
                recoveryStatus = .notice(String(localized: "没有发现旧缓存文档，无需导出原始备份。", comment: "Status shown when no legacy local cache backup is needed."))
                return
            }
            let backup = try recoveryController.prepareBackup()
            recoveryBackupDocument = MemoryExportFileDocument(data: backup.data)
            recoveryBackupFileName = backup.fileName
            let format = String(localized: "已准备 %lld 个旧缓存文档，请在系统面板中选择保存位置。", comment: "Status shown after preparing a legacy local cache backup. The placeholder is the document count.")
            recoveryStatus = .notice(String(format: format, Int64(backup.documentCount)))
            #if os(iOS)
            documentExportRequest = try makeDocumentExportRequest(
                kind: .recoveryBackup,
                fileName: backup.fileName,
                data: backup.data
            )
            #else
            isExportingRecoveryBackup = true
            #endif
        } catch {
            recoveryStatus = .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func handleRecoveryBackupCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let format = String(localized: "已导出旧缓存原始备份 %@。", comment: "Status shown after exporting a legacy local cache backup. The placeholder is the file name.")
            recoveryStatus = .success(String(format: format, url.lastPathComponent))
        case .failure(let error):
            recoveryStatus = isUserCancelled(error) ? .notice(String(localized: "已取消旧缓存原始备份导出，未写入文件。", comment: "Status shown when the user cancels legacy cache backup export.")) : .failed(importExportErrorMessage(for: error))
        }
    }

    @MainActor
    private func resetLegacyDocuments() {
        guard recoveryController.localDocumentCount() > 0 else {
            recoveryStatus = .notice(String(localized: "没有旧缓存文档需要重置。", comment: "Status shown when there are no legacy local cache documents to reset."))
            return
        }
        let resetCount = recoveryController.resetLocalDocuments()
        let format = String(localized: "已重置 %lld 个旧缓存文档。", comment: "Status shown after resetting legacy local cache documents. The placeholder is the reset document count.")
        recoveryStatus = .success(String(format: format, Int64(resetCount)))
    }

    @MainActor
    private func presentImport() {
        importExportStatus = .notice(String(localized: "请选择要导入的 JSON 文件。", comment: "Status shown before the user chooses a JSON import file."))
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
            importExportStatus = isUserCancelled(error) ? .notice(String(localized: "已取消导入，未读取文件。", comment: "Status shown when the user cancels memory import.")) : .failed(importExportErrorMessage(for: error))
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
            let summary = try importExportController.importMemory(
                from: data,
                conflictPolicy: importConflictPolicy
            )
            importExportStatus = .success(summary.statusMessage)
        } catch {
            importExportStatus = .failed(importExportErrorMessage(for: error))
        }
    }

    private func settingsErrorMessage(for error: Error) -> String {
        if let balanceError = error as? DeepSeekBalanceError {
            switch balanceError {
            case .invalidResponse:
                return String(localized: "DeepSeek 返回无效响应。", comment: "Error shown when the DeepSeek response cannot be parsed.")
            case .unavailableBalance:
                return String(localized: "Token 可认证，但账户余额不可用。请检查 DeepSeek 余额。", comment: "Status shown when DeepSeek accepts a token but balance is unavailable.")
            case .unauthorized:
                return String(localized: "Token 无效或已过期。", comment: "Status shown when a token is invalid during balance check.")
            case .httpStatus(let status):
                let format = String(localized: "DeepSeek 请求失败：HTTP %lld。", comment: "Error shown when an HTTP request to DeepSeek fails. The placeholder is the HTTP status code.")
                return String(format: format, Int64(status))
            }
        }

        if let keychainError = error as? KeychainCredentialError {
            switch keychainError {
            case .unhandledStatus(let status):
                let format = String(localized: "系统凭据存储失败：%lld。", comment: "Error shown when Keychain storage fails. The placeholder is the OSStatus code.")
                return String(format: format, Int64(status))
            }
        }

        return String(localized: "操作失败，请稍后重试。", comment: "Generic settings operation failure.")
    }

    private func importExportErrorMessage(for error: Error) -> String {
        SettingsErrorMessageFactory.importExportMessage(for: error)
    }

    #if os(iOS)
    @MainActor
    private func makeDocumentExportRequest(
        kind: SettingsDocumentExportKind,
        fileName: String,
        data: Data
    ) throws -> SettingsDocumentExportRequest {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordSceneExports", isDirectory: true)
        let exportDirectory = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let fileURL = exportDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return SettingsDocumentExportRequest(kind: kind, fileURL: fileURL)
    }

    @MainActor
    private func completeDocumentExport(
        _ request: SettingsDocumentExportRequest,
        result: Result<URL, Error>
    ) {
        documentExportRequest = nil
        try? FileManager.default.removeItem(at: request.fileURL.deletingLastPathComponent())
        switch request.kind {
        case .memory:
            handleExportCompletion(result)
        case .recoveryBackup:
            handleRecoveryBackupCompletion(result)
        }
    }
    #endif

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

enum SettingsErrorMessageFactory {
    static func importExportMessage(for error: Error) -> String {
        if let importExportError = error as? MemoryImportExportError {
            switch importExportError {
            case .invalidJSON:
                return String(localized: "导入文件不是有效的 WordScene JSON。", comment: "Error shown when the import file is not valid WordScene JSON.")
            case .unsupportedSchemaVersion:
                return String(localized: "导入文件版本不支持，请升级 App 后重试。", comment: "Error shown when an import file requires a newer app version.")
            case .checksumMismatch:
                return String(localized: "导入文件校验失败，文件可能已被修改或损坏。", comment: "Error shown when an import file checksum does not match.")
            }
        }

        if let persistenceError = error as? LocalPersistenceStoreError {
            switch persistenceError {
            case .unreadableDocument:
                return String(localized: "本地旧缓存无法读取。请先在“数据存储”导出旧缓存原始备份，再重置旧缓存文档。", comment: "Recovery error shown when a legacy local cache document cannot be read.")
            case .unsupportedSchemaVersion:
                return String(localized: "本地旧缓存来自更新版本的 App。请先升级 WordScene；不要直接重置，除非已经导出旧缓存原始备份。", comment: "Recovery error shown when a legacy local cache document requires a newer app version.")
            }
        }

        return error.localizedDescription.isEmpty ? String(localized: "导入导出失败，请稍后重试。", comment: "Generic import/export failure.") : error.localizedDescription
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
            return String(localized: "粘贴 DeepSeek Token，保存后即可翻译。", comment: "Setup hint for the API token field.")
        case .saved:
            return String(localized: "Token 已保存在本机。", comment: "Status shown after saving an API token.")
        case .testing:
            return String(localized: "正在测试 DeepSeek 连接...", comment: "Status while validating a DeepSeek token.")
        case .valid:
            return String(localized: "连接成功，Token 已保存。", comment: "Status shown after a successful DeepSeek connection test.")
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
    case notice(String)
    case working(String)
    case success(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return String(localized: "备份或迁移收藏内容。", comment: "Short import/export helper text.")
        case .notice(let message), .working(let message), .success(let message), .failed(let message):
            return message
        }
    }

    static var privacyNotice: String {
        String(localized: "导出文件包含收藏内容，请妥善保管。", comment: "Practical note shown before exporting saved memory.")
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "lock.doc"
        case .notice:
            return "info.circle"
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
        case .idle, .notice:
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
    case notice(String)
    case working(String)
    case success(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return String(localized: "旧缓存维护只处理早期本机文档，可先导出原始备份再重置。", comment: "Description for legacy local cache recovery tools.")
        case .notice(let message):
            return message
        case .working(let message), .success(let message), .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "wrench.and.screwdriver"
        case .notice:
            return "info.circle"
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
        case .idle, .notice:
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

#if os(iOS)
private enum SettingsDocumentExportKind {
    case memory
    case recoveryBackup
}

private struct SettingsDocumentExportRequest: Identifiable {
    let id = UUID()
    let kind: SettingsDocumentExportKind
    let fileURL: URL
}

private struct SettingsDocumentExporter: UIViewControllerRepresentable {
    let fileURL: URL
    let onCompletion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(fallbackURL: fileURL, onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let fallbackURL: URL
        private let onCompletion: (Result<URL, Error>) -> Void

        init(fallbackURL: URL, onCompletion: @escaping (Result<URL, Error>) -> Void) {
            self.fallbackURL = fallbackURL
            self.onCompletion = onCompletion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onCompletion(.success(urls.first ?? controller.directoryURL ?? fallbackURL))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        }
    }
}
#endif

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

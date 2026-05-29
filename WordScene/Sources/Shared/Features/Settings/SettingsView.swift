import SwiftUI

#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @AppStorage("allowsAnonymousCrashReports") private var allowsAnonymousCrashReports = false
    @State private var apiToken = ""
    @State private var tokenStatus: SettingsTokenStatus = .idle
    @Environment(\.adaptiveLayout) private var adaptiveLayout

    private let credentialStore = KeychainCredentialStore()
    private let balanceClient = DeepSeekBalanceClient()

    var body: some View {
        #if os(macOS)
        macSettingsBody
        #else
        mobileSettingsBody
        #endif
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
                        privacyCard
                        importExportCard
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        deepSeekCard
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

            Section("导入导出") {
                settingValueRow("导出文件名", value: "memory-book-export-YYYYMMDD.json")
                settingValueRow("范围", value: "全量导入 / 全量导出")

                HStack {
                    Spacer()
                    Button {
                        // Import workflow will be connected after persistence is finalized.
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        // Export workflow will be connected after persistence is finalized.
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
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

    private var importExportCard: some View {
        SettingsCard(title: "导入导出", systemImage: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: 14) {
                settingValueRow("导出文件名", value: "memory-book-export-YYYYMMDD.json")
                settingValueRow("范围", value: "全量导入 / 全量导出")

                HStack(spacing: 10) {
                    Button {
                        // Import workflow will be connected after persistence is finalized.
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        // Export workflow will be connected after persistence is finalized.
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
        }
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

    private func settingsErrorMessage(for error: Error) -> String {
        if let balanceError = error as? DeepSeekBalanceError {
            switch balanceError {
            case .invalidResponse:
                return "DeepSeek 返回无效响应。"
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

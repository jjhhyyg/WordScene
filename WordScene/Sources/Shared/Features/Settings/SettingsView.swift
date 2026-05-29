import SwiftUI

#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @AppStorage("allowsAnonymousCrashReports") private var allowsAnonymousCrashReports = false
    @State private var apiToken = ""
    @Environment(\.adaptiveLayout) private var adaptiveLayout

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

                HStack {
                    Spacer()
                    Button {
                        // Balance endpoint validation will be connected in the next milestone.
                    } label: {
                        Label("测试连接", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("测试 DeepSeek Token")
                }
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

                Button {
                    // Balance endpoint validation will be connected in the next milestone.
                } label: {
                    Label("测试连接", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("测试 DeepSeek Token")
            }
        }
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

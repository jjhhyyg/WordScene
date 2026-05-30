import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var memoryItems: [MemoryItem] = []
    @State private var history: [TranslationRecord] = []
    @State private var hasLoaded = false
    @State private var persistenceErrorMessage: String?
    @Environment(\.appDataController) private var dataController
    @Environment(\.adaptiveLayout) private var adaptiveLayout

    private let searchIndex = MemorySearchIndex()

    private var memoryStore: MemoryLibraryRepository {
        dataController.memoryLibrary
    }

    private var historyStore: TranslationHistoryRepository {
        dataController.translationHistory
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [MemorySearchResult] {
        searchIndex.search(query: query, memoryItems: memoryItems, history: history)
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView("正在加载搜索索引...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let persistenceErrorMessage {
                ContentUnavailableView(
                    "无法加载搜索索引",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(persistenceErrorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "搜索收藏",
                    systemImage: "magnifyingglass",
                    description: Text("支持原文、译文、语言和中文拼音搜索。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView(
                    "没有找到匹配内容",
                    systemImage: "magnifyingglass",
                    description: Text("可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(results.count) 个结果")
                                .font(.headline)
                            Spacer()
                            Text("收藏 \(memoryItems.count) · 历史 \(history.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(results) { result in
                                SearchResultRow(
                                    result: result,
                                    onSaveHistory: result.kind == .history ? {
                                        saveHistoryRecord(result.translationRecord)
                                    } : nil,
                                    onDeleteMemory: result.kind == .memory ? {
                                        deleteMemoryItem(id: result.memoryItem.id)
                                    } : nil,
                                    onDeleteHistory: result.kind == .history ? {
                                        deleteHistoryRecord(id: result.sourceID)
                                    } : nil
                                )
                            }
                        }
                    }
                    .frame(maxWidth: pageMaxWidth, alignment: .leading)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 18)
                    .padding(.bottom, adaptiveLayout.pageBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "搜索单词、短语、句子")
        .onAppear {
            loadSearchData()
        }
        .onReceive(dataController.dataChangeMonitor.$revision.dropFirst()) { _ in
            loadSearchData()
        }
    }

    private var pageMaxWidth: CGFloat {
        adaptiveLayout.usesCompactContent ? .infinity : 920
    }

    private var pageHorizontalPadding: CGFloat {
        adaptiveLayout.pageHorizontalPadding
    }

    private var pageBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }

    private func loadSearchData() {
        do {
            memoryItems = try memoryStore.loadOrThrow()
            history = try historyStore.loadOrThrow()
            persistenceErrorMessage = nil
        } catch {
            memoryItems = []
            history = []
            persistenceErrorMessage = "本地搜索数据读取失败：\(error.localizedDescription)"
        }
        hasLoaded = true
    }

    private func saveHistoryRecord(_ record: TranslationRecord) {
        let updatedItems = memoryStore.adding(record, to: memoryItems)
        do {
            try memoryStore.saveOrThrow(updatedItems)
            memoryItems = updatedItems
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "收藏保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteMemoryItem(id: UUID) {
        let updatedItems = memoryStore.removing(id: id, from: memoryItems)
        do {
            try memoryStore.saveOrThrow(updatedItems)
            memoryItems = updatedItems
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "收藏删除失败：\(error.localizedDescription)"
        }
    }

    private func deleteHistoryRecord(id: UUID) {
        let updatedHistory = historyStore.removing(id: id, from: history)
        do {
            try historyStore.saveOrThrow(updatedHistory)
            history = updatedHistory
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "翻译历史删除失败：\(error.localizedDescription)"
        }
    }
}

private struct SearchResultRow: View {
    let result: MemorySearchResult
    let onSaveHistory: (() -> Void)?
    let onDeleteMemory: (() -> Void)?
    let onDeleteHistory: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label(result.kind.title, systemImage: result.kind.systemImage)
                    .font(.caption)
                    .foregroundStyle(result.kind.tint)

                Spacer()

                Text(languageDirectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let onSaveHistory {
                    Button {
                        onSaveHistory()
                    } label: {
                        Image(systemName: "bookmark")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("保存到收藏")
                    .accessibilityIdentifier("search.history.save")
                }

                if let onDeleteMemory {
                    Button(role: .destructive) {
                        onDeleteMemory()
                    } label: {
                        Image(systemName: "trash")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("删除收藏")
                    .accessibilityIdentifier("search.memory.delete")
                }

                if let onDeleteHistory {
                    Button(role: .destructive) {
                        onDeleteHistory()
                    } label: {
                        Image(systemName: "trash")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("删除历史")
                    .accessibilityIdentifier("search.history.delete")
                }
            }

            Text(result.sourceText)
                .font(.headline)
                .textSelection(.enabled)
                .lineLimit(3)

            Text(result.translatedText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(4)

            if !result.note.isEmpty {
                Label(result.note, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(panelBorder, lineWidth: 1)
        }
    }

    private var languageDirectionText: String {
        "\(result.sourceLanguage.title) 到 \(result.targetLanguage.title)"
    }

    private var panelBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(.secondarySystemGroupedBackground)
        #endif
    }

    private var panelBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor).opacity(0.72)
        #else
        return Color(.separator).opacity(0.3)
        #endif
    }
}

private extension MemorySearchResult.Kind {
    var title: String {
        switch self {
        case .memory:
            return "收藏"
        case .history:
            return "历史"
        }
    }

    var systemImage: String {
        switch self {
        case .memory:
            return "bookmark.fill"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .memory:
            return .accentColor
        case .history:
            return .secondary
        }
    }
}

import SwiftUI

struct HistoryView: View {
    @State private var query = ""
    @State private var memoryItems: [MemoryItem] = []
    @State private var history: [TranslationRecord] = []
    @State private var hasLoaded = false
    @State private var persistenceErrorMessage: String?
    @State private var isConfirmingDeleteAll = false
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

    private var matchingHistory: [TranslationRecord] {
        guard !trimmedQuery.isEmpty else {
            return history
        }

        return searchIndex
            .search(query: query, memoryItems: [], history: history)
            .map(\.translationRecord)
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView("正在加载翻译历史...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                historyList
                #else
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        historyHeader

                        if let persistenceErrorMessage {
                            Label(persistenceErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        historyContent
                    }
                    .frame(maxWidth: pageMaxWidth, alignment: .leading)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, adaptiveLayout.pageBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle("翻译历史")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .alert("删除全部翻译历史？", isPresented: $isConfirmingDeleteAll) {
            Button("全部删除", role: .destructive) {
                deleteAllHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会清空本机历史，并通过同步删除其他设备上的历史记录。")
        }
        .onAppear {
            loadHistoryData()
        }
        .onReceive(dataController.dataChangeMonitor.$revision.dropFirst()) { _ in
            loadHistoryData()
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

    private var searchFieldBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(.secondarySystemGroupedBackground)
        #endif
    }

    private var searchFieldBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor).opacity(0.72)
        #else
        return Color(.separator).opacity(0.3)
        #endif
    }

    #if os(iOS)
    private var historyList: some View {
        List {
            Section {
                historyHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if let persistenceErrorMessage {
                    Label(persistenceErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 6, leading: pageHorizontalPadding, bottom: 6, trailing: pageHorizontalPadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                historySummaryRow
                    .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                historyListRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var historyListRows: some View {
        if let persistenceErrorMessage, history.isEmpty {
            ContentUnavailableView(
                "无法读取翻译历史",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if history.isEmpty {
            ContentUnavailableView(
                "还没有翻译历史",
                systemImage: "clock.arrow.circlepath",
                description: Text("完成翻译后，最近 100 条记录会显示在这里。")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if matchingHistory.isEmpty {
            ContentUnavailableView(
                "没有找到匹配内容",
                systemImage: "magnifyingglass",
                description: Text("可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(matchingHistory) { record in
                historyListRow(record)
            }
        }
    }

    private func historyListRow(_ record: TranslationRecord) -> some View {
        HistoryRecordRow(
            record: record,
            onSave: {
                saveHistoryRecord(record)
            },
            onDelete: {
                deleteHistoryRecord(id: record.id)
            }
        )
        .listRowInsets(EdgeInsets(top: 7, leading: pageHorizontalPadding, bottom: 7, trailing: pageHorizontalPadding))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    #endif

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            Text("翻译历史")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("history.title")
            #endif

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索翻译历史", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("history.search.field")

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清空搜索")
                    .accessibilityIdentifier("history.search.clear")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(searchFieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(searchFieldBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let persistenceErrorMessage, history.isEmpty {
            ContentUnavailableView(
                "无法读取翻译历史",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if history.isEmpty {
            ContentUnavailableView(
                "还没有翻译历史",
                systemImage: "clock.arrow.circlepath",
                description: Text("完成翻译后，最近 100 条记录会显示在这里。")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if matchingHistory.isEmpty {
            ContentUnavailableView(
                "没有找到匹配内容",
                systemImage: "magnifyingglass",
                description: Text("可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                historySummaryRow

                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(matchingHistory) { record in
                        HistoryRecordRow(
                            record: record,
                            onSave: {
                                saveHistoryRecord(record)
                            },
                            onDelete: {
                                deleteHistoryRecord(id: record.id)
                            }
                        )
                    }
                }
            }
        }
    }

    private var historySummaryRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(trimmedQuery.isEmpty ? "翻译历史 \(history.count) 条" : "\(matchingHistory.count) 个结果")
                .font(.headline)
            Spacer()
            Button(role: .destructive) {
                isConfirmingDeleteAll = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(history.isEmpty)
            .accessibilityLabel("删除全部翻译历史")
            .accessibilityIdentifier("history.deleteAll")
        }
    }

    private func loadHistoryData() {
        do {
            memoryItems = try memoryStore.loadOrThrow()
            history = try historyStore.loadOrThrow()
            persistenceErrorMessage = nil
        } catch {
            memoryItems = []
            history = []
            persistenceErrorMessage = "翻译历史读取失败：\(error.localizedDescription)"
        }
        hasLoaded = true
    }

    private func saveHistoryRecord(_ record: TranslationRecord) {
        let updatedItems = memoryStore.adding(record, to: memoryItems)
        let updatedHistory = historyStore.removing(id: record.id, from: history)
        do {
            try memoryStore.saveOrThrow(updatedItems)
            try historyStore.saveOrThrow(updatedHistory)
            memoryItems = updatedItems
            history = updatedHistory
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "收藏保存失败：\(error.localizedDescription)"
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

    private func deleteAllHistory() {
        do {
            try historyStore.deleteAllOrThrow()
            history = []
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "翻译历史清空失败：\(error.localizedDescription)"
        }
    }
}

private struct HistoryRecordRow: View {
    let record: TranslationRecord
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        #if os(iOS)
        ConfirmingSwipeRow(
            leadingAction: deleteSwipeAction,
            trailingAction: saveSwipeAction
        ) {
            rowContent
        }
        #else
        rowContent
        #endif
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label(languageDirectionText, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(record.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if os(macOS)
                Button {
                    onSave()
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("保存到收藏")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("删除历史")
                #endif
            }

            Text(record.sourceText)
                .font(.headline)
                .textSelection(.enabled)
                .lineLimit(4)

            Text(record.translatedText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(5)
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
        "\(record.sourceLanguage.title) 到 \(record.targetLanguage.title)"
    }

    private var saveSwipeAction: ConfirmingSwipeAction {
        ConfirmingSwipeAction(
            title: "收藏",
            systemImage: "bookmark",
            tint: .accentColor,
            accessibilityIdentifier: "history.swipe.save"
        ) {
            onSave()
        }
    }

    private var deleteSwipeAction: ConfirmingSwipeAction {
        ConfirmingSwipeAction(
            title: "删除",
            systemImage: "trash",
            tint: .red,
            accessibilityIdentifier: "history.swipe.delete"
        ) {
            onDelete()
        }
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

extension MemorySearchResult.Kind {
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

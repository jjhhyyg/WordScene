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
                ProgressView(String(localized: "正在加载翻译历史...", comment: "Loading indicator while translation history is being read."))
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
        .navigationTitle(String(localized: "翻译历史", comment: "Navigation title for the translation history screen."))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .alert(String(localized: "删除全部翻译历史？", comment: "Confirmation title before deleting all translation history."), isPresented: $isConfirmingDeleteAll) {
            Button(String(localized: "全部删除", comment: "Destructive button that deletes all items."), role: .destructive) {
                deleteAllHistory()
            }
            Button(String(localized: "取消", comment: "Cancel button title."), role: .cancel) {}
        } message: {
            Text(String(localized: "此操作会清空本机历史，并通过同步删除其他设备上的历史记录。", comment: "Warning shown before deleting all translation history."))
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
                String(localized: "无法读取翻译历史", comment: "Empty state title when translation history cannot be read."),
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if history.isEmpty {
            ContentUnavailableView(
                String(localized: "还没有翻译历史", comment: "Empty state title when there is no translation history."),
                systemImage: "clock.arrow.circlepath",
                description: Text(String(localized: "完成翻译后，最近 100 条记录会显示在这里。", comment: "Empty state description for translation history."))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if matchingHistory.isEmpty {
            ContentUnavailableView(
                String(localized: "没有找到匹配内容", comment: "Empty state title when search returns no matches."),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。", comment: "Search empty state suggestion."))
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
            Text(String(localized: "翻译历史", comment: "Large title for the translation history screen."))
                .font(.largeTitle.bold())
                .accessibilityIdentifier("history.title")
            #endif

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(String(localized: "搜索翻译历史", comment: "Placeholder for searching translation history."), text: $query)
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
                    .accessibilityLabel(String(localized: "清空搜索", comment: "Accessibility label for clearing the search field."))
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
                String(localized: "无法读取翻译历史", comment: "Empty state title when translation history cannot be read."),
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if history.isEmpty {
            ContentUnavailableView(
                String(localized: "还没有翻译历史", comment: "Empty state title when there is no translation history."),
                systemImage: "clock.arrow.circlepath",
                description: Text(String(localized: "完成翻译后，最近 100 条记录会显示在这里。", comment: "Empty state description for translation history."))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if matchingHistory.isEmpty {
            ContentUnavailableView(
                String(localized: "没有找到匹配内容", comment: "Empty state title when search returns no matches."),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。", comment: "Search empty state suggestion."))
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
            Text(trimmedQuery.isEmpty ? historyCountText(history.count) : resultCountText(matchingHistory.count))
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
            .accessibilityLabel(String(localized: "删除全部翻译历史", comment: "Accessibility label for the button that deletes all translation history."))
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
            let format = String(localized: "翻译历史读取失败：%@", comment: "Error shown when translation history cannot be loaded. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
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
            let format = String(localized: "收藏保存失败：%@", comment: "Error shown when a history item cannot be saved to the library. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func deleteHistoryRecord(id: UUID) {
        let updatedHistory = historyStore.removing(id: id, from: history)
        do {
            try historyStore.saveOrThrow(updatedHistory)
            history = updatedHistory
            persistenceErrorMessage = nil
        } catch {
            let format = String(localized: "翻译历史删除失败：%@", comment: "Error shown when a history item cannot be deleted. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func deleteAllHistory() {
        do {
            try historyStore.deleteAllOrThrow()
            history = []
            persistenceErrorMessage = nil
        } catch {
            let format = String(localized: "翻译历史清空失败：%@", comment: "Error shown when all translation history cannot be deleted. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func historyCountText(_ count: Int) -> String {
        let format = String(localized: "翻译历史 %lld 条", comment: "Summary count for translation history items. The placeholder is the item count.")
        return String(format: format, Int64(count))
    }

    private func resultCountText(_ count: Int) -> String {
        let format = String(localized: "%lld 个结果", comment: "Summary count for search results. The placeholder is the result count.")
        return String(format: format, Int64(count))
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
                .accessibilityLabel(String(localized: "保存到收藏", comment: "Accessibility label for saving a history item to the library."))

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "删除历史", comment: "Accessibility label for deleting a history item."))
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
        let format = String(localized: "%@ 到 %@", comment: "Language direction label. The placeholders are source language and target language.")
        return String(format: format, record.sourceLanguage.title, record.targetLanguage.title)
    }

    private var saveSwipeAction: ConfirmingSwipeAction {
        ConfirmingSwipeAction(
            title: String(localized: "收藏", comment: "Swipe action title for saving to the library."),
            systemImage: "bookmark",
            tint: .accentColor,
            accessibilityIdentifier: "history.swipe.save"
        ) {
            onSave()
        }
    }

    private var deleteSwipeAction: ConfirmingSwipeAction {
        ConfirmingSwipeAction(
            title: String(localized: "删除", comment: "Swipe action title for deleting an item."),
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
            return String(localized: "收藏", comment: "Search result kind for saved memory items.")
        case .history:
            return String(localized: "历史", comment: "Search result kind for translation history items.")
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

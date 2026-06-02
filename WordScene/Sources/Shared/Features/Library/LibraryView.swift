import SwiftUI

private enum LibraryFilter: Hashable {
    case all
    case starred
}

struct LibraryView: View {
    @State private var items: [MemoryItem] = []
    @State private var query = ""
    @State private var hasLoaded = false
    @State private var persistenceErrorMessage: String?
    @State private var isShowingManualAdd = false
    @State private var editingItem: MemoryItem?
    @State private var filter: LibraryFilter = .all
    @State private var isConfirmingDeleteAll = false
    @State private var isCheckingSync = false
    @State private var syncEventStatus: AppSyncEventStatus?
    @State private var scheduledReloadTask: Task<Void, Never>?
    @Environment(\.appDataController) private var dataController
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appThemePalette) private var themePalette

    private var store: MemoryLibraryRepository {
        dataController.memoryLibrary
    }

    private let searchIndex = MemorySearchIndex()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [MemorySearchResult] {
        searchIndex.search(query: query, memoryItems: filteredItems, history: [])
    }

    private var filteredItems: [MemoryItem] {
        switch filter {
        case .all:
            return items
        case .starred:
            return items.filter(\.isStarred)
        }
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView(String(localized: "正在加载收藏...", comment: "Loading indicator while saved memory items are being read."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                libraryList
                #else
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        libraryHeader

                        if let persistenceErrorMessage {
                            Label(persistenceErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        libraryContent
                    }
                    .frame(maxWidth: pageMaxWidth, alignment: .leading)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, adaptiveLayout.pageBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await refreshLibraryAndSyncStatus()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "收藏", comment: "Navigation title for the saved memory library."))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $isShowingManualAdd) {
            MemoryItemEditorSheet(title: String(localized: "手动新增", comment: "Title for manually adding a saved memory item.")) { draft in
                addManualItem(draft)
            }
        }
        .sheet(item: $editingItem) { item in
            MemoryItemEditorSheet(
                title: String(localized: "编辑收藏", comment: "Title for editing a saved memory item."),
                initialDraft: ManualMemoryItemDraft(item: item),
                allowsAutoSource: true
            ) { draft in
                updateItem(id: item.id, draft: draft)
            }
        }
        .alert(String(localized: "删除全部收藏？", comment: "Confirmation title before deleting all saved memory items."), isPresented: $isConfirmingDeleteAll) {
            Button(String(localized: "全部删除", comment: "Destructive button that deletes all items."), role: .destructive) {
                deleteAllItems()
            }
            Button(String(localized: "取消", comment: "Cancel button title."), role: .cancel) {}
        } message: {
            Text(String(localized: "此操作会删除全部收藏，并同步到其他设备。", comment: "Warning shown before deleting all saved memory items."))
        }
        .onAppear {
            syncEventStatus = dataController.syncEventMonitor.status
            loadLibraryData()
        }
        .onReceive(dataController.dataChangeMonitor.$revision.dropFirst()) { _ in
            loadLibraryData()
        }
        .onReceive(dataController.syncEventMonitor.$status) { status in
            syncEventStatus = status
            if status.hasSuccessfulCloudImport {
                scheduleLibraryReload()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                loadLibraryData()
            }
        }
    }

    private var gridColumns: [GridItem] {
        if adaptiveLayout.usesCompactContent {
            return [GridItem(.flexible(minimum: 0), spacing: 14)]
        }

        return [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 14)]
    }

    private var pageMaxWidth: CGFloat {
        adaptiveLayout.usesCompactContent ? .infinity : 1120
    }

    private var pageHorizontalPadding: CGFloat {
        adaptiveLayout.pageHorizontalPadding
    }

    private var emptyStateBottomPadding: CGFloat {
        adaptiveLayout.pageBottomPadding + 28
    }

    private var pageBackground: Color {
        if themePalette.usesCustomPalette {
            return themePalette.background
        }

        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }

    private var searchFieldBackground: Color {
        if themePalette.usesCustomPalette {
            return themePalette.surface
        }

        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(.secondarySystemGroupedBackground)
        #endif
    }

    private var searchFieldBorder: Color {
        if themePalette.usesCustomPalette {
            return themePalette.primary.opacity(0.18)
        }

        #if os(macOS)
        return Color(nsColor: .separatorColor).opacity(0.72)
        #else
        return Color(.separator).opacity(0.3)
        #endif
    }

    private var canAddManualItem: Bool {
        hasLoaded && !(persistenceErrorMessage != nil && items.isEmpty)
    }

    #if os(iOS)
    private var libraryList: some View {
        List {
            Section {
                libraryHeader
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
                librarySummary
                    .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                libraryListRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await refreshLibraryAndSyncStatus()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var libraryListRows: some View {
        if let persistenceErrorMessage, items.isEmpty {
            ContentUnavailableView(
                String(localized: "无法读取收藏", comment: "Empty state title when saved memory cannot be read."),
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if !trimmedQuery.isEmpty, searchResults.isEmpty {
            ContentUnavailableView(
                String(localized: "没有找到匹配内容", comment: "Empty state title when search returns no matches."),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。", comment: "Search empty state suggestion."))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if items.isEmpty {
            emptyLibraryState
                .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if filteredItems.isEmpty {
            ContentUnavailableView(
                String(localized: "没有星标收藏", comment: "Empty state title when the starred saved items filter is empty."),
                systemImage: "star",
                description: Text(String(localized: "给重要收藏加星标后，可在这里快速筛选。", comment: "Empty state description for starred saved items."))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if !trimmedQuery.isEmpty {
            ForEach(searchResults) { result in
                memoryListRow(result.memoryItem)
            }
        } else {
            ForEach(filteredItems) { item in
                memoryListRow(item)
            }
        }
    }

    private func memoryListRow(_ item: MemoryItem) -> some View {
        MemoryItemRow(
            item: item,
            onToggleStar: {
                toggleStar(id: item.id)
            },
            onEdit: {
                editingItem = item
            },
            onDelete: {
                deleteItem(id: item.id)
            }
        )
        .listRowInsets(EdgeInsets(top: 7, leading: pageHorizontalPadding, bottom: 7, trailing: pageHorizontalPadding))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    #endif

    private var librarySyncBadgeText: String {
        if isCheckingSync {
            return String(localized: "正在同步", comment: "Short status shown while checking library sync state.")
        }

        return (syncEventStatus ?? dataController.syncEventMonitor.status).librarySyncBadgeText
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            HStack(alignment: .center, spacing: 12) {
                Text(String(localized: "收藏", comment: "Large title for the saved memory library."))
                    .font(.largeTitle.bold())
                    .foregroundStyle(themePalette.usesCustomPalette ? themePalette.primary : Color.primary)
                    .accessibilityIdentifier("library.title")

                Spacer()

                Button {
                    isShowingManualAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canAddManualItem)
                .accessibilityLabel(String(localized: "手动新增", comment: "Accessibility label for manually adding a saved memory item."))
                .accessibilityIdentifier("library.header.manualAdd")
            }
            #endif

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(String(localized: "搜索单词、短语、句子", comment: "Placeholder for searching saved memory items."), text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("library.search.field")

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
                    .accessibilityIdentifier("library.search.clear")
                }

                #if os(macOS)
                Divider()
                    .frame(height: 18)

                Button {
                    isShowingManualAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!canAddManualItem)
                .accessibilityLabel(String(localized: "手动新增", comment: "Accessibility label for manually adding a saved memory item."))
                .accessibilityIdentifier("library.header.manualAdd")
                #endif
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
    private var libraryContent: some View {
        if let persistenceErrorMessage, items.isEmpty {
            ContentUnavailableView(
                String(localized: "无法读取收藏", comment: "Empty state title when saved memory cannot be read."),
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if !trimmedQuery.isEmpty {
            searchResultsContent
        } else if items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                librarySummary
                emptyLibraryState
            }
        } else if filteredItems.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                librarySummary
                ContentUnavailableView(
                    String(localized: "没有星标收藏", comment: "Empty state title when the starred saved items filter is empty."),
                    systemImage: "star",
                    description: Text(String(localized: "给重要收藏加星标后，可在这里快速筛选。", comment: "Empty state description for starred saved items."))
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            libraryGridContent
        }
    }

    private var librarySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(libraryCountText(items.count))
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    isConfirmingDeleteAll = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(items.isEmpty)
                .accessibilityLabel(String(localized: "删除全部收藏", comment: "Accessibility label for deleting all saved memory items."))
                .accessibilityIdentifier("library.deleteAll")

                Text(librarySyncBadgeText)
                    .font(.caption)
                    .foregroundStyle(themePalette.usesCustomPalette ? themePalette.primary.opacity(0.72) : Color.secondary)
                    .accessibilityIdentifier("library.sync.badge")
            }
            .foregroundStyle(themePalette.usesCustomPalette ? themePalette.primary : Color.primary)

            Picker(String(localized: "收藏筛选", comment: "Picker label for filtering saved memory items."), selection: $filter) {
                Text(String(localized: "全部", comment: "Filter option that shows all saved memory items.")).tag(LibraryFilter.all)
                Text(String(localized: "星标", comment: "Filter option that shows starred saved memory items.")).tag(LibraryFilter.starred)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("library.filter")
        }
    }

    private var libraryGridContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            librarySummary

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                ForEach(filteredItems) { item in
                    MemoryItemRow(
                        item: item,
                        onToggleStar: {
                            toggleStar(id: item.id)
                        },
                        onEdit: {
                            editingItem = item
                        },
                        onDelete: {
                            deleteItem(id: item.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchResults.isEmpty {
            ContentUnavailableView(
                String(localized: "没有找到匹配内容", comment: "Empty state title when search returns no matches."),
                systemImage: "magnifyingglass",
                description: Text(String(localized: "可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。", comment: "Search empty state suggestion."))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(resultCountText(searchResults.count))
                        .font(.headline)
                    Spacer()
                    Text(filter == .starred ? String(localized: "星标收藏", comment: "Caption for starred saved memory filter.") : compactLibraryCountText(items.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(searchResults) { result in
                        MemoryItemRow(
                            item: result.memoryItem,
                            onToggleStar: {
                                toggleStar(id: result.sourceID)
                            },
                            onEdit: {
                                editingItem = result.memoryItem
                            },
                            onDelete: {
                                deleteItem(id: result.sourceID)
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                String(localized: "还没有收藏", comment: "Empty state title when no saved memory exists."),
                systemImage: "bookmark",
                description: Text(String(localized: "翻译后点收藏，或手动新增一条本机记忆。", comment: "Empty state description for the saved memory library."))
            )
            .fixedSize(horizontal: false, vertical: true)

            Button {
                isShowingManualAdd = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                    Text(String(localized: "手动新增", comment: "Button title for manually adding a saved memory item."))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAddManualItem)
            .accessibilityIdentifier("library.empty.manualAdd")
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.bottom, emptyStateBottomPadding / 2)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func loadLibraryData() {
        do {
            items = try store.loadOrThrow()
            persistenceErrorMessage = nil
        } catch {
            items = []
            let format = String(localized: "收藏数据读取失败：%@", comment: "Error shown when saved memory cannot be loaded. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
        hasLoaded = true
    }

    private func scheduleLibraryReload() {
        scheduledReloadTask?.cancel()
        scheduledReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else {
                return
            }
            loadLibraryData()
        }
    }

    @MainActor
    private func refreshLibraryAndSyncStatus() async {
        isCheckingSync = true
        syncEventStatus = dataController.syncEventMonitor.status
        loadLibraryData()
        purgeExpiredTombstonesIfAllowed()

        do {
            try await Task.sleep(nanoseconds: 700_000_000)
        } catch {}

        syncEventStatus = dataController.syncEventMonitor.status
        isCheckingSync = false
    }

    private func purgeExpiredTombstonesIfAllowed() {
        let status = syncEventStatus ?? dataController.syncEventMonitor.status
        let policy: TombstoneRetentionPolicy?
        switch dataController.syncStatus {
        case .cloudKitConfigured:
            policy = status.hasSuccessfulCloudExport
                ? .cloudKit(days: 90, requiresSuccessfulExport: true)
                : nil
        case .localOnly, .localOnlyFallback, .unavailable:
            policy = .localOnly(days: 30)
        }

        guard let policy else {
            return
        }

        do {
            let purgedCount = try store.purgeExpiredDeletionTombstones(policy: policy)
            if purgedCount > 0 {
                loadLibraryData()
            }
        } catch {
            let format = String(localized: "删除记录清理失败：%@", comment: "Error shown when deletion tombstones cannot be purged. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func deleteItem(id: UUID) {
        do {
            try store.deleteOrThrow(id: id)
            items = store.removing(id: id, from: items)
            persistenceErrorMessage = nil
        } catch {
            let format = String(localized: "收藏删除失败：%@", comment: "Error shown when a saved memory item cannot be deleted. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func deleteAllItems() {
        do {
            try store.deleteAllOrThrow()
            items = []
            persistenceErrorMessage = nil
        } catch {
            let format = String(localized: "收藏清空失败：%@", comment: "Error shown when all saved memory items cannot be deleted. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func toggleStar(id: UUID) {
        do {
            if let updatedItem = try store.toggleStarOrThrow(id: id),
               let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                items[index] = updatedItem
            }
            persistenceErrorMessage = nil
        } catch {
            let format = String(localized: "星标更新失败：%@", comment: "Error shown when a saved memory star cannot be updated. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func updateItem(id: UUID, draft: ManualMemoryItemDraft) -> Bool {
        guard let original = items.first(where: { $0.id == id }) else {
            return false
        }

        let replacement = MemoryItem(
            id: id,
            sourceText: draft.sourceText,
            translatedText: draft.translatedText,
            sourceLanguage: draft.sourceLanguage,
            targetLanguage: draft.targetLanguage,
            note: draft.note,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            isStarred: original.isStarred
        )
        let updatedItems = store.updatingItem(replacement, in: items)
        guard updatedItems != items else {
            return false
        }

        do {
            try store.saveOrThrow(updatedItems)
            items = updatedItems
            persistenceErrorMessage = nil
            return true
        } catch {
            let format = String(localized: "收藏更新失败：%@", comment: "Error shown when a saved memory item cannot be updated. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
            return false
        }
    }

    private func addManualItem(_ draft: ManualMemoryItemDraft) -> Bool {
        let now = Date()
        let item = MemoryItem(
            sourceText: draft.sourceText,
            translatedText: draft.translatedText,
            sourceLanguage: draft.sourceLanguage,
            targetLanguage: draft.targetLanguage,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        )
        let updatedItems = store.adding(item, to: items)
        guard updatedItems != items else {
            return false
        }

        do {
            try store.saveOrThrow(updatedItems)
            items = updatedItems
            persistenceErrorMessage = nil
            return true
        } catch {
            let format = String(localized: "手动新增失败：%@", comment: "Error shown when manually adding a saved memory item fails. The placeholder is the system error description.")
            persistenceErrorMessage = String(format: format, error.localizedDescription)
            return false
        }
    }

    private func libraryCountText(_ count: Int) -> String {
        let format = String(localized: "已收藏 %lld 条", comment: "Summary count for saved memory items. The placeholder is the item count.")
        return String(format: format, Int64(count))
    }

    private func compactLibraryCountText(_ count: Int) -> String {
        let format = String(localized: "收藏 %lld", comment: "Compact saved memory count shown next to search results. The placeholder is the item count.")
        return String(format: format, Int64(count))
    }

    private func resultCountText(_ count: Int) -> String {
        let format = String(localized: "%lld 个结果", comment: "Summary count for search results. The placeholder is the result count.")
        return String(format: format, Int64(count))
    }
}

private struct ManualMemoryItemDraft {
    var sourceText = ""
    var translatedText = ""
    var sourceLanguage: LanguageSelection = .en
    var targetLanguage: LanguageSelection = .zh
    var note = ""

    init() {}

    init(item: MemoryItem) {
        sourceText = item.sourceText
        translatedText = item.translatedText
        sourceLanguage = item.sourceLanguage
        targetLanguage = item.targetLanguage
        note = item.note
    }

    var canSave: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct MemoryItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ManualMemoryItemDraft()

    let title: String
    let allowsAutoSource: Bool
    let onSave: (ManualMemoryItemDraft) -> Bool

    init(
        title: String,
        initialDraft: ManualMemoryItemDraft = ManualMemoryItemDraft(),
        allowsAutoSource: Bool = false,
        onSave: @escaping (ManualMemoryItemDraft) -> Bool
    ) {
        self.title = title
        self.allowsAutoSource = allowsAutoSource
        self.onSave = onSave
        self._draft = State(initialValue: initialDraft)
    }

    var body: some View {
        #if os(macOS)
        macEditor
        #else
        mobileEditor
        #endif
    }

    #if os(macOS)
    private var macEditor: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("library.editor.title")

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    macSection(String(localized: "语言", comment: "Section title for language pickers in the saved memory editor.")) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                            GridRow {
                                Text(String(localized: "源语言", comment: "Picker label for source language."))
                                    .foregroundStyle(.secondary)
                                Picker(String(localized: "源语言", comment: "Picker label for source language."), selection: $draft.sourceLanguage) {
                                    ForEach(sourceLanguageOptions) { language in
                                        Text(language.title).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("library.editor.sourceLanguage")
                            }

                            GridRow {
                                Text(String(localized: "目标语言", comment: "Picker label for target language."))
                                    .foregroundStyle(.secondary)
                                Picker(String(localized: "目标语言", comment: "Picker label for target language."), selection: $draft.targetLanguage) {
                                    ForEach(LanguageSelection.targetOptions(excluding: draft.sourceLanguage)) { language in
                                        Text(language.title).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("library.editor.targetLanguage")
                            }
                        }
                    }

                    macSection(String(localized: "内容", comment: "Section title for memory item editor content fields.")) {
                        VStack(alignment: .leading, spacing: 12) {
                            macTextEditor(
                                title: String(localized: "原文", comment: "Section title for the source text field."),
                                text: $draft.sourceText,
                                identifier: "library.editor.sourceText"
                            )

                            macTextEditor(
                                title: String(localized: "译文", comment: "Section title for the translated text field."),
                                text: $draft.translatedText,
                                identifier: "library.editor.translatedText"
                            )
                        }
                    }

                    macSection(String(localized: "备注", comment: "Section title for the optional note field.")) {
                        TextField(String(localized: "可选", comment: "Placeholder for an optional note field."), text: $draft.note)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("library.editor.note")
                    }
                }
                .padding(24)
            }
            .background(macEditorBackground)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(String(localized: "取消", comment: "Cancel button title.")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("library.editor.cancel")

                Button(String(localized: "保存", comment: "Save button title.")) {
                    if onSave(draft) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
                .accessibilityIdentifier("library.editor.save")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 540, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: draft.sourceLanguage) { _, newSource in
            normalizeTargetLanguage(for: newSource)
        }
    }

    private func macSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
    }

    private func macTextEditor(title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 104)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
                }
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private var macEditorBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
    #endif

    private var mobileEditor: some View {
        NavigationStack {
            Form {
                Section(String(localized: "语言", comment: "Section title for language pickers in the saved memory editor.")) {
                    Picker(String(localized: "源语言", comment: "Picker label for source language."), selection: $draft.sourceLanguage) {
                        ForEach(sourceLanguageOptions) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .accessibilityIdentifier("library.editor.sourceLanguage")

                    Picker(String(localized: "目标语言", comment: "Picker label for target language."), selection: $draft.targetLanguage) {
                        ForEach(LanguageSelection.targetOptions(excluding: draft.sourceLanguage)) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .accessibilityIdentifier("library.editor.targetLanguage")
                }

                Section(String(localized: "原文", comment: "Section title for the source text field.")) {
                    TextEditor(text: $draft.sourceText)
                        .frame(minHeight: 96)
                        .accessibilityLabel(String(localized: "原文", comment: "Accessibility label for the source text field."))
                        .accessibilityIdentifier("library.editor.sourceText")
                }

                Section(String(localized: "译文", comment: "Section title for the translated text field.")) {
                    TextEditor(text: $draft.translatedText)
                        .frame(minHeight: 96)
                        .accessibilityLabel(String(localized: "译文", comment: "Accessibility label for the translated text field."))
                        .accessibilityIdentifier("library.editor.translatedText")
                }

                Section(String(localized: "备注", comment: "Section title for the optional note field.")) {
                    TextField(String(localized: "可选", comment: "Placeholder for an optional note field."), text: $draft.note)
                        .accessibilityIdentifier("library.editor.note")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 520)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", comment: "Cancel button title.")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("library.editor.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存", comment: "Save button title.")) {
                        if onSave(draft) {
                            dismiss()
                        }
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("library.editor.save")
                }
            }
            .onChange(of: draft.sourceLanguage) { _, newSource in
                normalizeTargetLanguage(for: newSource)
            }
        }
    }

    private func normalizeTargetLanguage(for newSource: LanguageSelection) {
        let targetOptions = LanguageSelection.targetOptions(excluding: newSource)
        if !targetOptions.contains(draft.targetLanguage) {
            draft.targetLanguage = targetOptions.first ?? .zh
        }
    }

    private var sourceLanguageOptions: [LanguageSelection] {
        allowsAutoSource ? LanguageSelection.sourceOptions : LanguageSelection.sourceOptions.filter { $0 != .auto }
    }
}

private struct MemoryItemRow: View {
    let item: MemoryItem
    let onToggleStar: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    init(
        item: MemoryItem,
        onToggleStar: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onToggleStar = onToggleStar
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        #if os(iOS)
        rowContent
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    onToggleStar()
                } label: {
                    Label(
                        item.isStarred ? String(localized: "取消星标", comment: "Swipe action title for removing a star from a saved memory item.") : String(localized: "星标", comment: "Swipe action title for starring a saved memory item."),
                        systemImage: item.isStarred ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
                .accessibilityIdentifier("library.swipe.star")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(String(localized: "删除", comment: "Swipe action title for deleting an item."), systemImage: "trash")
                }
                .tint(.red)
                .accessibilityIdentifier("library.swipe.delete")
            }
        #else
        rowContent
        #endif
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                #if os(iOS)
                if item.isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel(String(localized: "星标", comment: "Accessibility label for a starred saved memory item."))
                        .accessibilityIdentifier("library.item.star")
                }
                #endif

                Label(languageDirectionText, systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(item.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if os(macOS)
                Button {
                    onToggleStar()
                } label: {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(item.isStarred ? String(localized: "取消星标", comment: "Accessibility label for removing a star from a saved memory item.") : String(localized: "星标", comment: "Accessibility label for starring a saved memory item."))
                .accessibilityIdentifier("library.item.star")
                #endif

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "编辑收藏", comment: "Accessibility label for editing a saved memory item."))
                .accessibilityIdentifier("library.item.edit")

                #if os(macOS)
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "删除收藏", comment: "Accessibility label for deleting a saved memory item."))
                .accessibilityIdentifier("library.item.delete")
                #endif
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.sourceText)
                    .font(.headline)
                    .textSelection(.enabled)
                    .lineLimit(4)

                Text(item.translatedText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(5)
            }

            if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()

                Label(item.note, systemImage: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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
        let format = String(localized: "%@ 到 %@", comment: "Language direction label. The placeholders are source language and target language.")
        return String(format: format, item.displaySourceLanguage.title, item.targetLanguage.title)
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

#Preview("Library") {
    NavigationStack {
        LibraryView()
    }
}

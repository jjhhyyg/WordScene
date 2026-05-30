import SwiftUI

struct ConfirmingSwipeAction {
    let title: String
    let systemImage: String
    let tint: Color
    let accessibilityIdentifier: String
    let perform: () -> Void
}

struct ConfirmingSwipeRow<Content: View>: View {
    private enum SwipeSide {
        case leading
        case trailing
    }

    let leadingAction: ConfirmingSwipeAction
    let trailingAction: ConfirmingSwipeAction
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var lockedSide: SwipeSide?
    @State private var confirmedSide: SwipeSide?
    @State private var confirmationProgress = 0.0
    @State private var confirmationTask: Task<Void, Never>?

    private let maximumOffset: CGFloat = 88
    private let confirmationDuration: TimeInterval = 0.38

    var body: some View {
        ZStack {
            actionBackground

            content
                .offset(x: offset)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.88), value: offset)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }

                    let nextOffset = cappedOffset(for: value.translation.width)
                    offset = nextOffset
                    updateConfirmation(for: nextOffset)
                }
                .onEnded { value in
                    let finalOffset = cappedOffset(for: value.translation.width)
                    let action: ConfirmingSwipeAction?

                    if finalOffset >= maximumOffset, confirmedSide == .leading {
                        action = leadingAction
                    } else if finalOffset <= -maximumOffset, confirmedSide == .trailing {
                        action = trailingAction
                    } else {
                        action = nil
                    }

                    resetSwipeState()

                    action?.perform()
                }
        )
        .onDisappear {
            confirmationTask?.cancel()
        }
    }

    private var actionBackground: some View {
        HStack {
            SwipeActionIndicator(
                action: leadingAction,
                progress: lockedSide == .leading ? confirmationProgress : 0,
                isConfirmed: confirmedSide == .leading,
                isActive: offset > 0
            )
            .padding(.leading, 18)
            .opacity(offset > 0 ? 1 : 0)

            Spacer()

            SwipeActionIndicator(
                action: trailingAction,
                progress: lockedSide == .trailing ? confirmationProgress : 0,
                isConfirmed: confirmedSide == .trailing,
                isActive: offset < 0
            )
            .padding(.trailing, 18)
            .opacity(offset < 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundTint)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var backgroundTint: Color {
        if offset > 0 {
            return leadingAction.tint.opacity(0.16)
        }

        if offset < 0 {
            return trailingAction.tint.opacity(0.16)
        }

        return .clear
    }

    private func cappedOffset(for translation: CGFloat) -> CGFloat {
        min(max(translation, -maximumOffset), maximumOffset)
    }

    private func updateConfirmation(for nextOffset: CGFloat) {
        if nextOffset >= maximumOffset {
            beginConfirmation(for: .leading)
        } else if nextOffset <= -maximumOffset {
            beginConfirmation(for: .trailing)
        } else if lockedSide != nil {
            cancelConfirmation()
        }
    }

    private func beginConfirmation(for side: SwipeSide) {
        guard lockedSide != side else {
            return
        }

        confirmationTask?.cancel()
        lockedSide = side
        confirmedSide = nil
        confirmationProgress = 0

        withAnimation(.linear(duration: confirmationDuration)) {
            confirmationProgress = 1
        }

        confirmationTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(confirmationDuration * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard lockedSide == side else {
                    return
                }

                confirmedSide = side
            }
        }
    }

    private func cancelConfirmation() {
        confirmationTask?.cancel()
        lockedSide = nil
        confirmedSide = nil
        withAnimation(.easeOut(duration: 0.12)) {
            confirmationProgress = 0
        }
    }

    private func resetSwipeState() {
        confirmationTask?.cancel()
        lockedSide = nil
        confirmedSide = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            offset = 0
            confirmationProgress = 0
        }
    }
}

private struct SwipeActionIndicator: View {
    let action: ConfirmingSwipeAction
    let progress: Double
    let isConfirmed: Bool
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(action.tint.opacity(isConfirmed ? 0.2 : 0.12))
                .frame(width: 42, height: 42)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(action.tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: 42, height: 42)
                .rotationEffect(.degrees(-90))

            Image(systemName: action.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(action.tint)
                .symbolVariant(isConfirmed ? .fill : .none)
                .scaleEffect(isConfirmed ? 1.08 : 1.0)
                .symbolEffect(.bounce, value: isConfirmed)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isConfirmed)
        }
        .accessibilityIdentifier(action.accessibilityIdentifier)
        .opacity(isActive ? 1 : 0)
    }
}

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
                ProgressView("正在加载收藏...")
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
        .navigationTitle("收藏")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $isShowingManualAdd) {
            MemoryItemEditorSheet(title: "手动新增") { draft in
                addManualItem(draft)
            }
        }
        .sheet(item: $editingItem) { item in
            MemoryItemEditorSheet(
                title: "编辑收藏",
                initialDraft: ManualMemoryItemDraft(item: item),
                allowsAutoSource: true
            ) { draft in
                updateItem(id: item.id, draft: draft)
            }
        }
        .alert("删除全部收藏？", isPresented: $isConfirmingDeleteAll) {
            Button("全部删除", role: .destructive) {
                deleteAllItems()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除全部收藏，并同步到其他设备。")
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
                "无法读取收藏",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(persistenceErrorMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(EdgeInsets(top: 8, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if !trimmedQuery.isEmpty, searchResults.isEmpty {
            ContentUnavailableView(
                "没有找到匹配内容",
                systemImage: "magnifyingglass",
                description: Text("可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。")
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
                "没有星标收藏",
                systemImage: "star",
                description: Text("给重要收藏加星标后，可在这里快速筛选。")
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
            return "正在同步"
        }

        return (syncEventStatus ?? dataController.syncEventMonitor.status).librarySyncBadgeText
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            HStack(alignment: .center, spacing: 12) {
                Text("收藏")
                    .font(.largeTitle.bold())
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
                .accessibilityLabel("手动新增")
                .accessibilityIdentifier("library.header.manualAdd")
            }
            #endif

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索单词、短语、句子", text: $query)
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
                    .accessibilityLabel("清空搜索")
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
                .accessibilityLabel("手动新增")
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
                "无法读取收藏",
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
                    "没有星标收藏",
                    systemImage: "star",
                    description: Text("给重要收藏加星标后，可在这里快速筛选。")
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
                Text("已收藏 \(items.count) 条")
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
                .accessibilityLabel("删除全部收藏")
                .accessibilityIdentifier("library.deleteAll")

                Text(librarySyncBadgeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("library.sync.badge")
            }

            Picker("收藏筛选", selection: $filter) {
                Text("全部").tag(LibraryFilter.all)
                Text("星标").tag(LibraryFilter.starred)
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
                "没有找到匹配内容",
                systemImage: "magnifyingglass",
                description: Text("可以缩短关键词，或尝试拼音、汉字、语言等不同搜索方式。")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(searchResults.count) 个结果")
                        .font(.headline)
                    Spacer()
                    Text(filter == .starred ? "星标收藏" : "收藏 \(items.count)")
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
                "还没有收藏",
                systemImage: "bookmark",
                description: Text("翻译后点收藏，或手动新增一条本机记忆。")
            )
            .fixedSize(horizontal: false, vertical: true)

            Button {
                isShowingManualAdd = true
            } label: {
                Label("手动新增", systemImage: "plus")
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
            persistenceErrorMessage = "收藏数据读取失败：\(error.localizedDescription)"
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
            persistenceErrorMessage = "删除记录清理失败：\(error.localizedDescription)"
        }
    }

    private func deleteItem(id: UUID) {
        do {
            try store.deleteOrThrow(id: id)
            items = store.removing(id: id, from: items)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "收藏删除失败：\(error.localizedDescription)"
        }
    }

    private func deleteAllItems() {
        do {
            try store.deleteAllOrThrow()
            items = []
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "收藏清空失败：\(error.localizedDescription)"
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
            persistenceErrorMessage = "星标更新失败：\(error.localizedDescription)"
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
            persistenceErrorMessage = "收藏更新失败：\(error.localizedDescription)"
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
            persistenceErrorMessage = "手动新增失败：\(error.localizedDescription)"
            return false
        }
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
        NavigationStack {
            Form {
                Section("语言") {
                    Picker("源语言", selection: $draft.sourceLanguage) {
                        ForEach(sourceLanguageOptions) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    Picker("目标语言", selection: $draft.targetLanguage) {
                        ForEach(LanguageSelection.targetOptions(excluding: draft.sourceLanguage)) { language in
                            Text(language.title).tag(language)
                        }
                    }
                }

                Section("原文") {
                    TextEditor(text: $draft.sourceText)
                        .frame(minHeight: 96)
                        .accessibilityLabel("原文")
                }

                Section("译文") {
                    TextEditor(text: $draft.translatedText)
                        .frame(minHeight: 96)
                        .accessibilityLabel("译文")
                }

                Section("备注") {
                    TextField("可选", text: $draft.note)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 520)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if onSave(draft) {
                            dismiss()
                        }
                    }
                    .disabled(!draft.canSave)
                }
            }
            .onChange(of: draft.sourceLanguage) { _, newSource in
                let targetOptions = LanguageSelection.targetOptions(excluding: newSource)
                if !targetOptions.contains(draft.targetLanguage) {
                    draft.targetLanguage = targetOptions.first ?? .zh
                }
            }
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
        ConfirmingSwipeRow(
            leadingAction: deleteSwipeAction,
            trailingAction: starSwipeAction
        ) {
            rowContent
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
                        .accessibilityLabel("星标")
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
                .accessibilityLabel(item.isStarred ? "取消星标" : "星标")
                #endif

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("编辑收藏")

                #if os(macOS)
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("删除收藏")
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
        "\(item.sourceLanguage.title) 到 \(item.targetLanguage.title)"
    }

    private var starSwipeAction: ConfirmingSwipeAction {
        ConfirmingSwipeAction(
            title: item.isStarred ? "取消星标" : "星标",
            systemImage: item.isStarred ? "star.slash" : "star",
            tint: .yellow,
            accessibilityIdentifier: "library.swipe.star"
        ) {
            onToggleStar()
        }
    }

    private var deleteSwipeAction: ConfirmingSwipeAction {
        ConfirmingSwipeAction(
            title: "删除",
            systemImage: "trash",
            tint: .red,
            accessibilityIdentifier: "library.swipe.delete"
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

#Preview("Library") {
    NavigationStack {
        LibraryView()
    }
}

import SwiftUI

struct LibraryView: View {
    @State private var items: [MemoryItem] = []
    @State private var hasLoaded = false
    @State private var persistenceErrorMessage: String?
    @State private var isShowingManualAdd = false
    @State private var editingItem: MemoryItem?
    @Environment(\.appDataController) private var dataController
    @Environment(\.adaptiveLayout) private var adaptiveLayout

    private var store: MemoryLibraryRepository {
        dataController.memoryLibrary
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView("正在加载收藏...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let persistenceErrorMessage, items.isEmpty {
                ContentUnavailableView(
                    "无法读取收藏",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(persistenceErrorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyLibraryState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let persistenceErrorMessage {
                            Label(persistenceErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("已收藏 \(items.count) 条")
                                .font(.headline)
                            Spacer()
                            Text("本机保存")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                            ForEach(items) { item in
                                MemoryItemRow(
                                    item: item,
                                    onSaveNote: { note in
                                        saveNote(for: item.id, note: note)
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
        .navigationTitle("收藏")
        .toolbar {
            Button {
                isShowingManualAdd = true
            } label: {
                Label("手动新增", systemImage: "plus")
            }
            .disabled(!canAddManualItem)
            .accessibilityIdentifier("library.toolbar.manualAdd")
        }
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
        .onAppear {
            loadItems()
        }
        .onReceive(dataController.dataChangeMonitor.$revision.dropFirst()) { _ in
            loadItems()
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

    private var canAddManualItem: Bool {
        hasLoaded && !(persistenceErrorMessage != nil && items.isEmpty)
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
        .padding(.bottom, emptyStateBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadItems() {
        do {
            items = try store.loadOrThrow()
            persistenceErrorMessage = nil
        } catch {
            items = []
            persistenceErrorMessage = "收藏数据读取失败：\(error.localizedDescription)"
        }
        hasLoaded = true
    }

    private func saveNote(for id: UUID, note: String) {
        let updatedItems = store.updatingNote(for: id, note: note, in: items)
        do {
            try store.saveOrThrow(updatedItems)
            items = updatedItems
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "备注保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteItem(id: UUID) {
        let updatedItems = store.removing(id: id, from: items)
        do {
            try store.saveOrThrow(updatedItems)
            items = updatedItems
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "收藏删除失败：\(error.localizedDescription)"
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
            updatedAt: original.updatedAt
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
    let onSaveNote: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var noteDraft: String
    @State private var isEditingNote: Bool

    init(
        item: MemoryItem,
        onSaveNote: @escaping (String) -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onSaveNote = onSaveNote
        self.onEdit = onEdit
        self.onDelete = onDelete
        self._noteDraft = State(initialValue: item.note)
        self._isEditingNote = State(initialValue: item.note.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label(languageDirectionText, systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(item.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("编辑收藏")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("删除收藏")
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

            Divider()

            noteSection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(panelBorder, lineWidth: 1)
        }
        .onChange(of: item.note) { _, newNote in
            if !isEditingNote {
                noteDraft = newNote
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        if isEditingNote {
            HStack(alignment: .center, spacing: 8) {
                TextField("添加备注", text: $noteDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("library.note.editor")
                    .onSubmit {
                        saveNoteAndExitEditing()
                    }

                Button {
                    saveNoteAndExitEditing()
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("保存备注")
                .accessibilityIdentifier("library.note.save")
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                Label(noteDraft, systemImage: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 8)

                Button {
                    isEditingNote = true
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("编辑备注")
                .accessibilityIdentifier("library.note.edit")
            }
            .padding(.vertical, 6)
        }
    }

    private func saveNoteAndExitEditing() {
        noteDraft = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        onSaveNote(noteDraft)
        isEditingNote = noteDraft.isEmpty
    }

    private var languageDirectionText: String {
        "\(item.sourceLanguage.title) 到 \(item.targetLanguage.title)"
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

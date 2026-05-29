import SwiftUI

struct LibraryView: View {
    @State private var items: [MemoryItem] = []
    @State private var hasLoaded = false
    @Environment(\.adaptiveLayout) private var adaptiveLayout

    private let store = MemoryLibraryRepository()

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView("正在加载收藏...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "还没有收藏",
                    systemImage: "bookmark",
                    description: Text("翻译后点收藏，将单词、短语或句子保存为可学习条目。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationTitle("收藏")
        .onAppear {
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

    private var pageBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }

    private func loadItems() {
        items = store.load()
        hasLoaded = true
    }

    private func saveNote(for id: UUID, note: String) {
        items = store.updatingNote(for: id, note: note, in: items)
        store.save(items)
    }

    private func deleteItem(id: UUID) {
        items = store.removing(id: id, from: items)
        store.save(items)
    }
}

private struct MemoryItemRow: View {
    let item: MemoryItem
    let onSaveNote: (String) -> Void
    let onDelete: () -> Void

    @State private var noteDraft: String

    init(
        item: MemoryItem,
        onSaveNote: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onSaveNote = onSaveNote
        self.onDelete = onDelete
        self._noteDraft = State(initialValue: item.note)
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

            HStack(alignment: .center, spacing: 8) {
                TextField("添加备注", text: $noteDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onSaveNote(noteDraft)
                    }

                Button {
                    onSaveNote(noteDraft)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("保存备注")
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

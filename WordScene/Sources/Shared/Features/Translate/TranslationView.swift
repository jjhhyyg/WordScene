import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct TranslationView: View {
    @State private var sourceLanguage: LanguageSelection = .auto
    @State private var targetLanguage: LanguageSelection = .zh
    @State private var inputText = ""
    @State private var translationState: TranslationState = .idle
    @State private var lastTranslatedRecord: TranslationRecord?
    @State private var translationGeneration = 0
    @State private var didCopyTranslation = false
    @State private var didApplyUITestInput = false
    @State private var consumedHandoffIDs: Set<UUID> = []
    @State private var history: [TranslationRecord] = []
    @State private var memoryItems: [MemoryItem] = []
    @State private var persistenceWarningMessage: String?
    @State private var isClipboardPromptVisible = false
    @State private var didDismissClipboardPromptCandidate = false
    @EnvironmentObject private var routeCoordinator: AppRouteCoordinator
    @Environment(\.appDataController) private var dataController
    @Environment(\.translationRuntime) private var translationRuntime
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appThemePalette) private var themePalette

    private var historyStore: TranslationHistoryRepository {
        dataController.translationHistory
    }

    private var memoryStore: MemoryLibraryRepository {
        dataController.memoryLibrary
    }

    var body: some View {
        contentContainer
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            if adaptiveLayout.usesTabNavigation {
                Color.clear.frame(height: 88)
            }
        }
        #endif
        .navigationTitle(String(localized: "翻译", comment: "Main translation tab title and primary translate action."))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            loadHistory()
            loadMemoryItems()
            applyUITestInputIfNeeded()
            if let id = routeCoordinator.pendingShareHandoffID {
                applyShareHandoff(id: id)
            }
            #if os(iOS)
            refreshClipboardPrompt()
            #endif
        }
        .onReceive(dataController.dataChangeMonitor.$revision.dropFirst()) { _ in
            loadHistory()
            loadMemoryItems()
        }
        .onReceive(routeCoordinator.$pendingShareHandoffID.compactMap { $0 }) { id in
            applyShareHandoff(id: id)
        }
        .onChange(of: sourceLanguage) { _, _ in
            normalizeLanguageDirection()
        }
    }

    @ViewBuilder
    private var contentContainer: some View {
        #if os(macOS)
        GeometryReader { proxy in
            let layout = MacTranslationLayout(
                kind: MacTranslationLayout.Kind(
                    availableWidth: max(0, proxy.size.width - pageHorizontalPadding * 2)
                )
            )

            ScrollView {
                macDesktopContent(for: layout)
                    .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, pageBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pageBackground)
        }
        #else
        ScrollView {
            content
                .frame(maxWidth: pageMaxWidth, alignment: .leading)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, pageBottomPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground.ignoresSafeArea())
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if usesCompactPhoneLayout {
            VStack(alignment: .leading, spacing: 18) {
                translationHeader
                clipboardPromptBanner
                mobileTranslationPanel
                persistenceWarningBanner
            }
        } else if usesMacDesktopLayout {
            macDesktopContent
        } else {
            VStack(alignment: .leading, spacing: 18) {
                translationHeader
                commandBar
                persistenceWarningBanner
                clipboardPromptBanner

                if usesTwoColumnLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 18) {
                            inputPanel
                            resultPanel
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        inputPanel
                        #if os(macOS)
                        translationActionBar
                        #endif
                        resultPanel
                    }
                }
            }
        }
    }

    private var translationHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(localized: "翻译", comment: "Main translation tab title and primary translate action."))
                .font(.largeTitle.bold())
                .foregroundStyle(themePalette.usesCustomPalette ? themePalette.primary : Color.primary)
                .accessibilityIdentifier("translation.title")

            Spacer()

            #if os(iOS)
            Button {
                Task {
                    await translateInput()
                }
            } label: {
                Image(systemName: translationState.isTranslating ? "arrow.triangle.2.circlepath" : "arrow.right.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!hasTranslatableInput || translationState.isTranslating)
            .accessibilityLabel(String(localized: "开始翻译", comment: "Accessibility label for the primary translate button."))
            .accessibilityIdentifier("translation.start")
            #endif
        }
    }

    private var macDesktopContent: some View {
        macDesktopContent(for: MacTranslationLayout(kind: .expanded))
    }

    @ViewBuilder
    private func macDesktopContent(for layout: MacTranslationLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            macCommandBar(for: layout)
            persistenceWarningBanner

            switch layout.kind {
            case .compact:
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    inputPanel
                    resultPanel
                }

            case .regular:
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    HStack(alignment: .top, spacing: layout.columnSpacing) {
                        inputPanel
                            .frame(minWidth: 0, maxWidth: .infinity)
                        resultPanel
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }

            case .expanded:
                HStack(alignment: .top, spacing: layout.columnSpacing) {
                    inputPanel
                        .frame(minWidth: 300, maxWidth: .infinity)
                    resultPanel
                        .frame(minWidth: 340, maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func macCommandBar(for layout: MacTranslationLayout) -> some View {
        switch layout.kind {
        case .compact:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    languagePicker(
                        .source,
                        selection: $sourceLanguage,
                        options: LanguageSelection.sourceOptions,
                        maxWidth: 180
                    )
                    swapDirectionButton(systemImage: "arrow.left.arrow.right", buttonSize: 32)
                    languagePicker(
                        .target,
                        selection: $targetLanguage,
                        options: LanguageSelection.targetOptions(excluding: sourceLanguage),
                        maxWidth: 180
                    )
                    Spacer(minLength: 0)
                }

                actionControls(style: .macCommandBar)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .panelStyle()

        case .regular, .expanded:
            commandBar
        }
    }

    private var usesMacDesktopLayout: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    private var usesTwoColumnLayout: Bool {
        #if os(macOS)
        return true
        #else
        return adaptiveLayout.usesContentColumns && !dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var usesCompactPhoneLayout: Bool {
        #if os(macOS)
        return false
        #else
        return adaptiveLayout.usesCompactContent
        #endif
    }

    private var putsActionInCommandBar: Bool {
        #if os(iOS)
        return false
        #else
        usesTwoColumnLayout
        #endif
    }

    private var pageMaxWidth: CGFloat {
        if usesCompactPhoneLayout {
            return .infinity
        }

        return usesTwoColumnLayout ? 1180 : 720
    }

    private var pageHorizontalPadding: CGFloat {
        #if os(macOS)
        return 28
        #else
        return adaptiveLayout.pageHorizontalPadding
        #endif
    }

    private var pageBottomPadding: CGFloat {
        #if os(macOS)
        return 32
        #else
        return adaptiveLayout.pageBottomPadding
        #endif
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

    private var inputEditorMinHeight: CGFloat {
        if usesCompactPhoneLayout {
            return dynamicTypeSize.isAccessibilitySize ? 76 : 108
        }

        if usesTwoColumnLayout {
            #if os(macOS)
            return 340
            #else
            return 260
            #endif
        }

        return dynamicTypeSize.isAccessibilitySize ? 96 : 220
    }

    private var resultPanelMinHeight: CGFloat {
        if usesTwoColumnLayout {
            #if os(macOS)
            return 428
            #else
            return 360
            #endif
        }

        return dynamicTypeSize.isAccessibilitySize ? 170 : 220
    }

    private var commandBar: some View {
        Group {
            if usesTwoColumnLayout {
                HStack(alignment: .bottom, spacing: usesMacDesktopLayout ? 10 : 12) {
                    languagePicker(
                        .source,
                        selection: $sourceLanguage,
                        options: LanguageSelection.sourceOptions,
                        maxWidth: languagePickerMaxWidth
                    )
                    swapDirectionButton(systemImage: "arrow.left.arrow.right", buttonSize: 32)
                    languagePicker(
                        .target,
                        selection: $targetLanguage,
                        options: LanguageSelection.targetOptions(excluding: sourceLanguage),
                        maxWidth: languagePickerMaxWidth
                    )

                    Spacer(minLength: usesMacDesktopLayout ? 20 : 16)

                    if putsActionInCommandBar {
                        actionControls(style: usesMacDesktopLayout ? .macCommandBar : .commandBar)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    languagePicker(.source, selection: $sourceLanguage, options: LanguageSelection.sourceOptions)
                    swapDirectionButton(systemImage: "arrow.up.arrow.down", buttonSize: 32)
                        .frame(maxWidth: .infinity, alignment: .center)
                    languagePicker(.target, selection: $targetLanguage, options: LanguageSelection.targetOptions(excluding: sourceLanguage))
                }
            }
        }
        .panelStyle()
    }

    @ViewBuilder
    private var persistenceWarningBanner: some View {
        if let persistenceWarningMessage {
            Label(persistenceWarningMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var clipboardPromptBanner: some View {
        if isClipboardPromptVisible {
            HStack(spacing: 12) {
                Label(String(localized: "检测到剪贴板文本"), systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                ClipboardTranslatePasteControl { clipboardText in
                    Task {
                        await acceptClipboardText(clipboardText)
                    }
                }
                .frame(width: 120, height: 34)
                .accessibilityLabel(String(localized: "翻译剪贴板"))

                Button {
                    dismissClipboardPrompt()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "忽略剪贴板文本"))
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("translation.clipboardPrompt")
        }
    }
    #else
    private var clipboardPromptBanner: some View {
        EmptyView()
    }
    #endif

    private var mobileTranslationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    inlineLanguagePicker(.source, selection: $sourceLanguage, options: LanguageSelection.sourceOptions)
                    Spacer()

                    if !inputText.isEmpty {
                        Button {
                            clearTranslationDraft()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "清空输入", comment: "Accessibility label for clearing the translation input."))
                        .accessibilityIdentifier("translation.input.clear")
                    }
                }

                PromptedTextEditor(
                    text: $inputText,
                    prompt: String(localized: "输入要翻译的文本", comment: "Placeholder for the compact translation input field."),
                    minHeight: inputEditorMinHeight,
                    textStyle: .largePrompt,
                    accessibilityIdentifier: "translation.input.editor"
                )
                    .accessibilityLabel(String(localized: "待翻译文本", comment: "Accessibility label for the translation input editor."))
                    .accessibilityIdentifier("translation.input.editor")
            }
            .padding(.bottom, 10)

            ZStack {
                Divider()

                swapDirectionButton(systemImage: "arrow.up.arrow.down", buttonSize: 38, drawsBackground: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    inlineLanguagePicker(.target, selection: $targetLanguage, options: LanguageSelection.targetOptions(excluding: sourceLanguage))
                    Spacer()
                    Label(translationState.statusText, systemImage: translationState.statusSystemImage)
                        .font(.caption)
                        .foregroundStyle(translationState.statusTint)
                }

                translationResultContent(minHeight: dynamicTypeSize.isAccessibilitySize ? 72 : 92)
            }
            .padding(.top, 10)
        }
        .panelStyle()
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "输入", comment: "Heading for the translation input panel."))
                    .font(.headline)
                Spacer()
                if inputText.isEmpty {
                    Text("\(inputText.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel(inputCharacterCountAccessibilityLabel)
                } else {
                    HStack(spacing: 8) {
                        Text("\(inputText.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityLabel(inputCharacterCountAccessibilityLabel)

                        Button {
                            clearTranslationDraft()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "清空输入和译文", comment: "Accessibility label for clearing both the input and translated result."))
                        .accessibilityIdentifier("translation.input.clear")
                    }
                }
            }

                PromptedTextEditor(
                    text: $inputText,
                    prompt: String(localized: "输入要翻译的单词、短语或句子", comment: "Placeholder for the full translation input field."),
                    minHeight: inputEditorMinHeight,
                    contentPadding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
                    accessibilityIdentifier: "translation.input.editor"
                )
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(String(localized: "待翻译文本", comment: "Accessibility label for the translation input editor."))
                .accessibilityIdentifier("translation.input.editor")
        }
        .panelStyle()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var translationActionBar: some View {
        actionControls(style: usesTwoColumnLayout ? .commandBar : .fullWidth)
            .frame(maxWidth: usesTwoColumnLayout ? 420 : .infinity, alignment: .leading)
            .padding(.horizontal, usesTwoColumnLayout ? 18 : 0)
    }

    private var languagePickerMaxWidth: CGFloat {
        #if os(macOS)
        return 210
        #else
        return 170
        #endif
    }

    private func actionControls(style: ActionControlStyle) -> some View {
        return HStack(spacing: 12) {
            Button {
                Task {
                    await translateInput()
                }
            } label: {
                Label(translationState.isTranslating ? String(localized: "翻译中", comment: "Status while a translation request is running.") : String(localized: "翻译", comment: "Main translation tab title and primary translate action."), systemImage: translationState.isTranslating ? "arrow.triangle.2.circlepath" : "arrow.right.circle.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(width: style.primaryWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasTranslatableInput || translationState.isTranslating)
            .accessibilityLabel(String(localized: "开始翻译", comment: "Accessibility label for the primary translate button."))
            .accessibilityIdentifier("translation.start")
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: .command)
            #endif
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "结果", comment: "Heading for the translation result panel."))
                    .font(.headline)
                Spacer()
                Label(translationState.statusText, systemImage: translationState.statusSystemImage)
                    .font(.caption)
                    .foregroundStyle(translationState.statusTint)
            }

            translationResultContent(minHeight: resultPanelMinHeight)
        }
        .panelStyle()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func translationResultContent(minHeight: CGFloat) -> some View {
        Group {
            switch translationState {
            case .idle:
                ContentUnavailableView(
                    String(localized: "还没有翻译结果", comment: "Empty result title before a translation has run."),
                    systemImage: "text.bubble",
                    description: Text(String(localized: "配置 DeepSeek Token 后，输入内容即可开始翻译。", comment: "Empty result description before a translation has run."))
                )
            case .translating(let partialText):
                if partialText.isEmpty {
                    ProgressView(String(localized: "正在翻译...", comment: "Progress label while translating."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    streamingTranslationText(partialText)
                }
            case .translated(let text):
                finalTranslationText(text)
            case .failed(let message):
                ContentUnavailableView(
                    String(localized: "翻译失败", comment: "Error state title when translation fails."),
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func streamingTranslationText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(String(localized: "译文", comment: "Section title for translated text."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("translation.result.partialText")
        }
    }

    private func finalTranslationText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastTranslatedRecord {
                HStack(alignment: .center, spacing: 10) {
                    Text(String(localized: "译文", comment: "Section title for translated text."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if didCopyTranslation {
                        Label(String(localized: "已复制", comment: "Status label shown after copying translated text."), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    memoryTextButton(for: lastTranslatedRecord)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            ScrollView {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.top, lastTranslatedRecord == nil ? 14 : 0)
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("translation.result.finalText")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                copyTranslation(text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityHint(String(localized: "点击复制", comment: "Accessibility hint for copying translated text."))
            .accessibilityValue(text)
            .accessibilityIdentifier("translation.result.finalText")
        }
    }

    private var inputCharacterCountAccessibilityLabel: String {
        let format = String(localized: "输入字符数 %lld", comment: "Accessibility label for the translation input character count. The placeholder is the character count.")
        return String(format: format, Int64(inputText.count))
    }

    private func languagePicker(
        _ role: TranslationLanguagePickerRole,
        selection: Binding<LanguageSelection>,
        options: [LanguageSelection],
        maxWidth: CGFloat? = nil
    ) -> some View {
        let title = role.title
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(options) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.large)
            .lineLimit(1)
            .frame(maxWidth: maxWidth ?? (usesTwoColumnLayout ? 220 : .infinity), alignment: .leading)
            .accessibilityLabel(title)
            .accessibilityIdentifier(role.accessibilityIdentifier)
        }
        .frame(minWidth: usesTwoColumnLayout ? min(maxWidth ?? 220, 150) : 0)
    }

    private func inlineLanguagePicker(
        _ role: TranslationLanguagePickerRole,
        selection: Binding<LanguageSelection>,
        options: [LanguageSelection]
    ) -> some View {
        let title = role.title
        return Picker(title, selection: selection) {
            ForEach(options) { language in
                Text(language.title).tag(language)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.large)
        .font(.headline)
        .accessibilityLabel(title)
        .accessibilityIdentifier(role.accessibilityIdentifier)
    }

    private func swapDirectionButton(
        systemImage: String,
        buttonSize: CGFloat,
        drawsBackground: Bool = false
    ) -> some View {
        Button {
            swapLanguageDirection()
        } label: {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .frame(width: buttonSize, height: buttonSize)
                .background(drawsBackground ? pageBackground : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(canSwapLanguageDirection ? Color.accentColor : Color.secondary)
        .disabled(!canSwapLanguageDirection)
        .accessibilityLabel(String(localized: "交换翻译方向", comment: "Accessibility label for swapping translation source and target languages."))
        .accessibilityIdentifier("translation.swapDirection")
    }

    private func swapLanguageDirection() {
        if case .translated(let translatedText) = translationState {
            translationGeneration += 1
            inputText = translatedText
            translationState = .idle
            lastTranslatedRecord = nil
            didCopyTranslation = false
        }

        let swapped = currentLanguageDirection.swapped()
        sourceLanguage = swapped.source
        targetLanguage = swapped.target
    }

    private func normalizeLanguageDirection() {
        let normalized = currentLanguageDirection.normalized()
        sourceLanguage = normalized.source
        targetLanguage = normalized.target
    }

    private var canSwapLanguageDirection: Bool {
        currentLanguageDirection.canSwap
    }

    private var hasTranslatableInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentLanguageDirection: TranslationLanguageDirection {
        TranslationLanguageDirection(source: sourceLanguage, target: targetLanguage)
    }

    private func isSavedToMemory(_ record: TranslationRecord) -> Bool {
        memoryStore.item(matching: record, in: memoryItems) != nil
    }

    private func memoryTextButton(for record: TranslationRecord) -> some View {
        Button {
            toggleMemory(for: record)
        } label: {
            Label(
                isSavedToMemory(record) ? String(localized: "translation.result.savedToMemory", defaultValue: "已收藏", comment: "Button title when a translation result is already saved to memory.") : String(localized: "translation.result.saveToMemory", defaultValue: "收藏", comment: "Button title for saving a translation result to memory."),
                systemImage: isSavedToMemory(record) ? "bookmark.fill" : "bookmark"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.86)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(isSavedToMemory(record) ? String(localized: "translation.result.removeFromMemory.accessibility", defaultValue: "取消收藏", comment: "Accessibility label for removing a translation result from saved memory.") : String(localized: "translation.result.saveToMemory.accessibility", defaultValue: "收藏", comment: "Accessibility label for saving a translation result to memory."))
        .accessibilityIdentifier("translation.result.memory")
        #if os(macOS)
        .keyboardShortcut("s", modifiers: .command)
        #endif
    }

    @MainActor
    private func loadHistory() {
        do {
            history = try historyStore.loadOrThrow()
        } catch {
            history = []
            persistenceWarningMessage = String(
                format: String(localized: "翻译历史读取失败：%@", comment: "Warning shown when translation history cannot be loaded. The placeholder is the system error description."),
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func applyUITestInputIfNeeded() {
        guard !didApplyUITestInput,
              ProcessInfo.processInfo.arguments.contains("-WordSceneUITest") else {
            return
        }

        didApplyUITestInput = true
        let environment = ProcessInfo.processInfo.environment
        if let seededInput = environment["WORDSCENE_UI_TEST_TRANSLATION_INPUT"], !seededInput.isEmpty {
            inputText = seededInput
        }
        if let sourceValue = environment["WORDSCENE_UI_TEST_SOURCE_LANGUAGE"],
           let source = LanguageSelection(rawValue: sourceValue) {
            sourceLanguage = source
        }
        if let targetValue = environment["WORDSCENE_UI_TEST_TARGET_LANGUAGE"],
           let target = LanguageSelection(rawValue: targetValue) {
            targetLanguage = target
        }
        normalizeLanguageDirection()
    }

    @MainActor
    private func loadMemoryItems() {
        do {
            memoryItems = try memoryStore.loadOrThrow()
        } catch {
            memoryItems = []
            persistenceWarningMessage = String(
                format: String(localized: "收藏数据读取失败：%@", comment: "Warning shown when saved memory cannot be loaded. The placeholder is the system error description."),
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func toggleMemory(for record: TranslationRecord) {
        let updatedItems: [MemoryItem]
        if isSavedToMemory(record) {
            updatedItems = memoryStore.removing(record, from: memoryItems)
        } else {
            updatedItems = memoryStore.adding(record, to: memoryItems)
        }

        do {
            try memoryStore.saveOrThrow(updatedItems)
            memoryItems = updatedItems
            persistenceWarningMessage = nil
        } catch {
            persistenceWarningMessage = String(
                format: String(localized: "收藏保存失败：%@", comment: "Warning shown when saving a translation result to memory fails. The placeholder is the system error description."),
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func applyShareHandoff(id: UUID) {
        guard !consumedHandoffIDs.contains(id),
              let store = ShareExtensionHandoffStore(),
              let handoff = try? store.load(id: id) else {
            return
        }

        consumedHandoffIDs.insert(id)
        translationGeneration += 1
        sourceLanguage = handoff.sourceLanguage
        targetLanguage = handoff.targetLanguage
        inputText = handoff.sourceText
        isClipboardPromptVisible = false
        lastTranslatedRecord = handoff.translationRecord
        translationState = .translated(handoff.translatedText)
        didCopyTranslation = false
        persistenceWarningMessage = nil
        consumePendingShareOperations(using: store)
        try? store.delete(id: id)
        _ = routeCoordinator.consumePendingShareHandoffID()
    }

    @MainActor
    private func consumePendingShareOperations(using store: ShareExtensionHandoffStore) {
        guard let operations = try? store.consumePendingOperations() else {
            return
        }

        for operation in operations {
            switch operation {
            case .history(let handoff):
                let updatedHistory = historyStore.adding(handoff.translationRecord, to: history)
                do {
                    try historyStore.saveOrThrow(updatedHistory)
                    history = updatedHistory
                } catch {
                    persistenceWarningMessage = String(
                        format: String(localized: "翻译历史保存失败：%@", comment: "Warning shown when saving shared extension translation history fails. The placeholder is the system error description."),
                        error.localizedDescription
                    )
                }
            case .favorite(let handoff):
                let updatedItems = memoryStore.adding(MemoryItem(record: handoff.translationRecord), to: memoryItems)
                do {
                    try memoryStore.saveOrThrow(updatedItems)
                    memoryItems = updatedItems
                } catch {
                    persistenceWarningMessage = String(
                        format: String(localized: "收藏保存失败：%@", comment: "Warning shown when saving shared extension favorite fails. The placeholder is the system error description."),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    @MainActor
    private func clearTranslationDraft() {
        translationGeneration += 1
        inputText = ""
        translationState = .idle
        lastTranslatedRecord = nil
        didCopyTranslation = false
    }

    #if os(iOS)
    @MainActor
    private func refreshClipboardPrompt() {
        let hasClipboardText = UIPasteboard.general.hasStrings
        isClipboardPromptVisible = hasClipboardText
            && !didDismissClipboardPromptCandidate
            && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func acceptClipboardText(_ clipboardText: String) async {
        guard let prompt = TranslationClipboardPrompt.make(
            clipboardText: clipboardText,
            currentInput: inputText,
            dismissedText: nil
        ) else {
            isClipboardPromptVisible = false
            return
        }

        let action = prompt.acceptance(defaultTargetLanguage: TranslationPreferencesStore().defaultTargetLanguage)
        translationGeneration += 1
        inputText = action.inputText
        sourceLanguage = action.sourceLanguage
        targetLanguage = action.targetLanguage
        isClipboardPromptVisible = false
        await translateInput()
    }

    @MainActor
    private func dismissClipboardPrompt() {
        didDismissClipboardPromptCandidate = true
        isClipboardPromptVisible = false
    }
    #endif

    @MainActor
    private func copyTranslation(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif

        didCopyTranslation = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            didCopyTranslation = false
        }
    }

    @MainActor
    private func translateInput() async {
        let currentGeneration = translationGeneration + 1

        do {
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }

            translationGeneration = currentGeneration
            didCopyTranslation = false
            translationState = .translating("")
            lastTranslatedRecord = nil
            let normalizedDirection = currentLanguageDirection.normalized()
            sourceLanguage = normalizedDirection.source
            targetLanguage = normalizedDirection.target
            let workflow = TranslationWorkflow(
                credentialStore: translationRuntime.credentialStore,
                translationClient: translationRuntime.translationClient,
                historyStore: historyStore
            )
            for try await event in workflow.streamTranslation(
                text: inputText,
                source: normalizedDirection.source,
                target: normalizedDirection.target,
                currentHistory: history
            ) {
                guard currentGeneration == translationGeneration else {
                    return
                }

                switch event {
                case .partial(let partialText):
                    translationState = .translating(partialText)
                case .completed(let result):
                    lastTranslatedRecord = result.record
                    translationState = .translated(result.translatedText)
                    history = result.updatedHistory
                    persistenceWarningMessage = result.persistenceWarningMessage
                }
            }
        } catch {
            guard currentGeneration == translationGeneration,
                  !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            translationState = .failed(translationErrorMessage(for: error))
        }
    }

    private func translationErrorMessage(for error: Error) -> String {
        if let workflowError = error as? TranslationWorkflowError {
            switch workflowError {
            case .missingToken:
                return String(localized: "请先在设置中保存 DeepSeek API Token。", comment: "Error shown when translating without a saved API token.")
            }
        }

        if let translationError = error as? DeepSeekTranslationError {
            switch translationError {
            case .emptyInput:
                return String(localized: "请输入需要翻译的文本。", comment: "Error shown when the user tries to translate empty text.")
            case .emptyOutput:
                return String(localized: "DeepSeek 没有返回可用译文。", comment: "Error shown when the translation provider returns no usable translation.")
            case .incompleteOutput:
                return String(localized: "DeepSeek 输出被截断，请缩短文本后重试。", comment: "Error shown when the translation provider truncates the output.")
            case .filteredOutput:
                return String(localized: "DeepSeek 拒绝了该内容，请调整文本后重试。", comment: "Error shown when the translation provider refuses the content.")
            case .insufficientSystemResource:
                return String(localized: "DeepSeek 暂时资源不足，请稍后重试。", comment: "Error shown when the translation provider reports insufficient resources.")
            case .invalidResponse:
                return String(localized: "DeepSeek 返回无效响应。", comment: "Error shown when the DeepSeek response cannot be parsed.")
            case .unauthorized:
                return String(localized: "DeepSeek Token 无效或已过期。", comment: "Error shown when the translation API token is rejected.")
            case .httpStatus(let status):
                let format = String(localized: "DeepSeek 请求失败：HTTP %lld。", comment: "Error shown when an HTTP request to DeepSeek fails. The placeholder is the HTTP status code.")
                return String(format: format, Int64(status))
            case .timedOut:
                return String(localized: "DeepSeek 响应超时，请稍后重试或缩短文本。", comment: "Error shown when the translation provider does not respond before the timeout.")
            }
        }

        if let keychainError = error as? KeychainCredentialError {
            switch keychainError {
            case .unhandledStatus(let status):
                let format = String(localized: "读取系统凭据失败：%lld。", comment: "Error shown when reading from Keychain fails. The placeholder is the OSStatus code.")
                return String(format: format, Int64(status))
            }
        }

        return String(localized: "翻译请求失败，请检查网络后重试。", comment: "Generic translation request failure.")
    }
}

private enum TranslationLanguagePickerRole {
    case source
    case target

    var title: String {
        switch self {
        case .source:
            return String(localized: "源语言", comment: "Picker label for source language.")
        case .target:
            return String(localized: "目标语言", comment: "Picker label for target language.")
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .source:
            return "translation.sourceLanguage.picker"
        case .target:
            return "translation.targetLanguage.picker"
        }
    }
}

private enum TranslationState: Equatable {
    case idle
    case translating(String)
    case translated(String)
    case failed(String)

    var isTranslating: Bool {
        if case .translating = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return String(localized: "等待翻译", comment: "Idle status before a translation starts.")
        case .translating:
            return String(localized: "翻译中", comment: "Status while a translation request is running.")
        case .translated:
            return String(localized: "已翻译", comment: "Translation status after a successful translation.")
        case .failed:
            return String(localized: "需要处理", comment: "Status shown when translation needs user attention.")
        }
    }

    var statusSystemImage: String {
        switch self {
        case .idle:
            return "clock"
        case .translating:
            return "arrow.triangle.2.circlepath"
        case .translated:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusTint: Color {
        switch self {
        case .idle:
            return .secondary
        case .translating:
            return .accentColor
        case .translated:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct PanelStyle: ViewModifier {
    @Environment(\.appThemePalette) private var themePalette

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .padding(16)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(panelBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
        #else
        content
            .padding(18)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        #endif
    }

    private var panelBackground: Color {
        if themePalette.usesCustomPalette {
            return themePalette.surface
        }

        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(.secondarySystemGroupedBackground)
        #endif
    }

    private var panelBorder: Color {
        if themePalette.usesCustomPalette {
            return themePalette.primary.opacity(0.18)
        }

        #if os(macOS)
        return Color(nsColor: .separatorColor).opacity(0.72)
        #else
        return Color(.separator).opacity(0.3)
        #endif
    }
}

private struct PromptedTextEditor: View {
    @Binding var text: String

    let prompt: String
    let minHeight: CGFloat
    var textStyle: TextInputTextStyle = .body
    var contentPadding = EdgeInsets()
    var accessibilityIdentifier: String?

    var body: some View {
        PlatformPromptedTextView(
            text: $text,
            prompt: prompt,
            textStyle: textStyle,
            contentPadding: contentPadding,
            accessibilityIdentifier: accessibilityIdentifier
        )
        .frame(minHeight: minHeight)
    }
}

#if os(iOS)
private struct ClipboardTranslatePasteControl: UIViewRepresentable {
    let onPaste: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .capsule

        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.accessibilityIdentifier = "translation.clipboardPrompt.paste"
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
    }

    final class Coordinator: NSObject, UIPasteConfigurationSupporting {
        var pasteConfiguration: UIPasteConfiguration?
        var onPaste: (String) -> Void

        init(onPaste: @escaping (String) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                return
            }

            provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                guard let text = object as? NSString else {
                    return
                }

                let pastedText = String(text)
                DispatchQueue.main.async {
                    self?.onPaste(pastedText)
                }
            }
        }
    }
}
#endif

private enum TextInputTextStyle {
    case body
    case largePrompt

    #if os(macOS)
    var platformFont: NSFont {
        switch self {
        case .body:
            return .systemFont(ofSize: NSFont.systemFontSize)
        case .largePrompt:
            return .systemFont(ofSize: 20, weight: .semibold)
        }
    }
    #elseif os(iOS)
    var platformFont: UIFont {
        switch self {
        case .body:
            return .preferredFont(forTextStyle: .body)
        case .largePrompt:
            return .preferredFont(forTextStyle: .title2).weighted(.semibold)
        }
    }
    #endif
}

#if os(macOS)
private struct PlatformPromptedTextView: NSViewRepresentable {
    @Binding var text: String

    let prompt: String
    let textStyle: TextInputTextStyle
    let contentPadding: EdgeInsets
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.setAccessibilityIdentifier(accessibilityIdentifier)

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = contentPadding.nsSize
        textView.font = textStyle.platformFont
        textView.textColor = .labelColor
        textView.placeholder = prompt
        textView.string = text
        textView.setAccessibilityIdentifier(accessibilityIdentifier)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.text = $text
        scrollView.setAccessibilityIdentifier(accessibilityIdentifier)
        if textView.string != text {
            textView.string = text
        }
        if let textView = textView as? PlaceholderTextView {
            textView.placeholder = prompt
            textView.needsDisplay = true
        }
        textView.font = textStyle.platformFont
        textView.textContainerInset = contentPadding.nsSize
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
            textView.needsDisplay = true
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
    }
}

private extension EdgeInsets {
    var nsSize: NSSize {
        NSSize(width: leading, height: top)
    }
}
#elseif os(iOS)
private struct PlatformPromptedTextView: UIViewRepresentable {
    @Binding var text: String

    let prompt: String
    let textStyle: TextInputTextStyle
    let contentPadding: EdgeInsets
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = contentPadding.uiInsets
        textView.font = textStyle.platformFont
        textView.textColor = .label
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.text = text
        textView.accessibilityIdentifier = accessibilityIdentifier

        let placeholderLabel = UILabel()
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.numberOfLines = 0
        placeholderLabel.text = prompt
        placeholderLabel.font = textStyle.platformFont
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isHidden = !text.isEmpty
        placeholderLabel.tag = Coordinator.placeholderTag
        textView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: contentPadding.top),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: contentPadding.leading),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -contentPadding.trailing)
        ])

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        textView.accessibilityIdentifier = accessibilityIdentifier
        if textView.text != text {
            textView.text = text
        }

        textView.font = textStyle.platformFont
        textView.textContainerInset = contentPadding.uiInsets
        textView.textContainer.lineFragmentPadding = 0

        if let placeholderLabel = textView.viewWithTag(Coordinator.placeholderTag) as? UILabel {
            placeholderLabel.text = prompt
            placeholderLabel.font = textStyle.platformFont
            placeholderLabel.isHidden = !text.isEmpty
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        static let placeholderTag = 91001

        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            textView.viewWithTag(Self.placeholderTag)?.isHidden = !textView.text.isEmpty
        }
    }
}

private extension EdgeInsets {
    var uiInsets: UIEdgeInsets {
        UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

private extension UIFont {
    func weighted(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif

private struct MacTranslationLayout {
    enum Kind: Equatable {
        case compact
        case regular
        case expanded

        init(availableWidth: CGFloat) {
            if availableWidth < MacTranslationLayout.regularMinimumWidth {
                self = .compact
            } else if availableWidth < MacTranslationLayout.expandedMinimumWidth {
                self = .regular
            } else {
                self = .expanded
            }
        }
    }

    static let compactMaximumWidth: CGFloat = 760
    static let regularMinimumWidth: CGFloat = 820
    static let regularMaximumWidth: CGFloat = 1120
    static let expandedMinimumWidth: CGFloat = 1180
    static let expandedMaximumWidth: CGFloat = 1480

    let kind: Kind

    var contentMaxWidth: CGFloat {
        switch kind {
        case .compact:
            return Self.compactMaximumWidth
        case .regular:
            return Self.regularMaximumWidth
        case .expanded:
            return Self.expandedMaximumWidth
        }
    }

    var contextColumnWidth: CGFloat {
        min(max(contentMaxWidth * 0.23, 280), 340)
    }

    var columnSpacing: CGFloat {
        kind == .expanded ? 18 : 16
    }

    var sectionSpacing: CGFloat {
        kind == .compact ? 14 : 16
    }
}

private enum ActionControlStyle {
    case commandBar
    case macCommandBar
    case fullWidth

    var primaryWidth: CGFloat? {
        switch self {
        case .commandBar:
            return 92
        case .macCommandBar:
            return 104
        case .fullWidth:
            return nil
        }
    }

}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelStyle())
    }
}

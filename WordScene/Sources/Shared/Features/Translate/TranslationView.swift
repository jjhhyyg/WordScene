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
    @State private var history: [TranslationRecord] = []
    @State private var memoryItems: [MemoryItem] = []
    @State private var persistenceWarningMessage: String?
    @Environment(\.appDataController) private var dataController
    @Environment(\.adaptiveLayout) private var adaptiveLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let credentialStore = KeychainCredentialStore()
    private let translationClient = DeepSeekTranslationClient()
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
        .navigationTitle("翻译")
        .task {
            loadHistory()
            loadMemoryItems()
        }
        .onReceive(dataController.dataChangeMonitor.$revision.dropFirst()) { _ in
            loadHistory()
            loadMemoryItems()
        }
        .onChange(of: sourceLanguage) { _, _ in
            normalizeLanguageDirection()
        }
        .keyboardDismissControls()
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
                .padding(.top, 18)
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
                mobileTranslationPanel
                persistenceWarningBanner
                translationActionBar
            }
        } else if usesMacDesktopLayout {
            macDesktopContent
        } else {
            VStack(alignment: .leading, spacing: 18) {
                commandBar
                persistenceWarningBanner

                if usesTwoColumnLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 18) {
                            inputPanel
                            resultPanel
                        }

                        contextPanel
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        inputPanel
                        translationActionBar
                        resultPanel
                        contextPanel
                    }
                }
            }
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
                    contextPanelView(minHeight: 180)
                }

            case .regular:
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    HStack(alignment: .top, spacing: layout.columnSpacing) {
                        inputPanel
                            .frame(minWidth: 0, maxWidth: .infinity)
                        resultPanel
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }

                    contextPanelView(minHeight: 190)
                }

            case .expanded:
                HStack(alignment: .top, spacing: layout.columnSpacing) {
                    inputPanel
                        .frame(minWidth: 300, maxWidth: .infinity)
                    resultPanel
                        .frame(minWidth: 340, maxWidth: .infinity)
                    contextPanelView(minHeight: resultPanelMinHeight)
                        .frame(width: layout.contextColumnWidth)
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
                        "源语言",
                        selection: $sourceLanguage,
                        options: LanguageSelection.sourceOptions,
                        maxWidth: 180
                    )
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 32, alignment: .center)
                        .accessibilityHidden(true)
                    languagePicker(
                        "目标语言",
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

    private var usesContextSidebar: Bool {
        #if os(macOS)
        return usesMacDesktopLayout
        #else
        return false
        #endif
    }

    private var putsActionInCommandBar: Bool {
        usesTwoColumnLayout
    }

    private var pageMaxWidth: CGFloat {
        if usesCompactPhoneLayout {
            return .infinity
        }

        if usesContextSidebar {
            return 1260
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
                        "源语言",
                        selection: $sourceLanguage,
                        options: LanguageSelection.sourceOptions,
                        maxWidth: languagePickerMaxWidth
                    )
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 32, alignment: .center)
                        .accessibilityHidden(true)
                    languagePicker(
                        "目标语言",
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
                    languagePicker("源语言", selection: $sourceLanguage, options: LanguageSelection.sourceOptions)
                    languagePicker("目标语言", selection: $targetLanguage, options: LanguageSelection.targetOptions(excluding: sourceLanguage))
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

    private var mobileTranslationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    inlineLanguagePicker("源语言", selection: $sourceLanguage, options: LanguageSelection.sourceOptions)
                    Spacer()

                    if !inputText.isEmpty {
                        Button {
                            inputText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("清空输入")
                    }
                }

                PromptedTextEditor(
                    text: $inputText,
                    prompt: "输入要翻译的文本",
                    minHeight: inputEditorMinHeight,
                    textStyle: .largePrompt
                )
                    .accessibilityLabel("待翻译文本")
                    .accessibilityIdentifier("translation.input.editor")
            }
            .padding(.bottom, 10)

            ZStack {
                Divider()

                Button {
                    swapLanguageDirection()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.headline.weight(.bold))
                        .frame(width: 38, height: 38)
                        .background(pageBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSwapLanguageDirection ? Color.accentColor : Color.secondary)
                .disabled(!canSwapLanguageDirection)
                .accessibilityLabel("交换翻译方向")
                .accessibilityIdentifier("translation.swapDirection")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    inlineLanguagePicker("目标语言", selection: $targetLanguage, options: LanguageSelection.targetOptions(excluding: sourceLanguage))
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
                Text("输入")
                    .font(.headline)
                Spacer()
                Text("\(inputText.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("输入字符数 \(inputText.count)")
            }

            PromptedTextEditor(
                text: $inputText,
                prompt: "输入要翻译的单词、短语或句子",
                minHeight: inputEditorMinHeight,
                contentPadding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            )
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("待翻译文本")
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
        let hasInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 12) {
            Button {
                Task {
                    await translateInput()
                }
            } label: {
                Label(translationState.isTranslating ? "翻译中" : "翻译", systemImage: translationState.isTranslating ? "arrow.triangle.2.circlepath" : "arrow.right.circle.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(width: style.primaryWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasInput || translationState.isTranslating)
            .accessibilityLabel("开始翻译")
            .accessibilityIdentifier("translation.start")

            Button {
                inputText = ""
                translationState = .idle
                lastTranslatedRecord = nil
            } label: {
                Label("清空", systemImage: "xmark.circle")
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(width: style.secondaryWidth)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!hasInput)
            .opacity(hasInput ? 1 : 0)
            .accessibilityHidden(!hasInput)
            .accessibilityIdentifier("translation.clear")
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("结果")
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

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("翻译历史")
                    .font(.headline)
                Spacer()
                Label("最近", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            translationHistoryContent(minHeight: usesContextSidebar ? 360 : 160)
        }
        .panelStyle()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func contextPanelView(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("翻译历史")
                    .font(.headline)
                Spacer()
                Label("最近", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            translationHistoryContent(minHeight: minHeight)
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
                    "还没有翻译结果",
                    systemImage: "text.bubble",
                    description: Text("配置 DeepSeek Token 后，输入内容即可开始翻译。")
                )
            case .translating:
                ProgressView("正在翻译...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .translated(let text):
                VStack(alignment: .leading, spacing: 10) {
                    if let lastTranslatedRecord {
                        HStack(alignment: .center, spacing: 10) {
                            Text("译文")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    }
                }
            case .failed(let message):
                ContentUnavailableView(
                    "翻译失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func translationHistoryContent(minHeight: CGFloat) -> some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView(
                    "暂无翻译历史",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("翻译后会在这里显示最近记录、相关词和收藏状态。")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(history.prefix(6)) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(record.sourceLanguage.title)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                Text(record.targetLanguage.title)
                                Spacer()
                                Text(record.createdAt, style: .time)
                                memoryIconButton(for: record)
                                deleteHistoryIconButton(for: record)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(record.sourceText)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            Text(record.translatedText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
            }
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func languagePicker(
        _ title: String,
        selection: Binding<LanguageSelection>,
        options: [LanguageSelection],
        maxWidth: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .accessibilityIdentifier(languagePickerIdentifier(for: title))
        }
        .frame(minWidth: usesTwoColumnLayout ? min(maxWidth ?? 220, 150) : 0)
    }

    private func inlineLanguagePicker(
        _ title: String,
        selection: Binding<LanguageSelection>,
        options: [LanguageSelection]
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { language in
                Text(language.title).tag(language)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.large)
        .font(.headline)
        .accessibilityLabel(title)
        .accessibilityIdentifier(languagePickerIdentifier(for: title))
    }

    private func languagePickerIdentifier(for title: String) -> String {
        switch title {
        case "源语言":
            return "translation.sourceLanguage.picker"
        case "目标语言":
            return "translation.targetLanguage.picker"
        default:
            return "translation.language.picker"
        }
    }

    private func swapLanguageDirection() {
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
                isSavedToMemory(record) ? "已收藏" : "收藏",
                systemImage: isSavedToMemory(record) ? "bookmark.fill" : "bookmark"
            )
            .lineLimit(1)
            .minimumScaleFactor(0.86)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(isSavedToMemory(record) ? "取消收藏" : "收藏")
    }

    private func memoryIconButton(for record: TranslationRecord) -> some View {
        Button {
            toggleMemory(for: record)
        } label: {
            Image(systemName: isSavedToMemory(record) ? "bookmark.fill" : "bookmark")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(isSavedToMemory(record) ? "取消收藏" : "收藏")
    }

    private func deleteHistoryIconButton(for record: TranslationRecord) -> some View {
        Button(role: .destructive) {
            deleteHistoryRecord(id: record.id)
        } label: {
            Image(systemName: "trash")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel("删除历史")
        .accessibilityIdentifier("translation.history.delete")
    }

    @MainActor
    private func loadHistory() {
        do {
            history = try historyStore.loadOrThrow()
        } catch {
            history = []
            persistenceWarningMessage = "翻译历史读取失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadMemoryItems() {
        do {
            memoryItems = try memoryStore.loadOrThrow()
        } catch {
            memoryItems = []
            persistenceWarningMessage = "收藏数据读取失败：\(error.localizedDescription)"
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
            persistenceWarningMessage = "收藏保存失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteHistoryRecord(id: UUID) {
        let updatedHistory = historyStore.removing(id: id, from: history)
        do {
            try historyStore.saveOrThrow(updatedHistory)
            history = updatedHistory
            persistenceWarningMessage = nil
        } catch {
            persistenceWarningMessage = "翻译历史删除失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func translateInput() async {
        do {
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }

            translationState = .translating
            lastTranslatedRecord = nil
            let normalizedDirection = currentLanguageDirection.normalized()
            sourceLanguage = normalizedDirection.source
            targetLanguage = normalizedDirection.target
            let workflow = TranslationWorkflow(
                credentialStore: credentialStore,
                translationClient: translationClient,
                historyStore: historyStore
            )
            let result = try await workflow.translate(
                text: inputText,
                source: normalizedDirection.source,
                target: normalizedDirection.target,
                currentHistory: history
            )

            lastTranslatedRecord = result.record
            translationState = .translated(result.translatedText)
            history = result.updatedHistory
            persistenceWarningMessage = result.persistenceWarningMessage
        } catch {
            translationState = .failed(translationErrorMessage(for: error))
        }
    }

    private func translationErrorMessage(for error: Error) -> String {
        if let workflowError = error as? TranslationWorkflowError {
            switch workflowError {
            case .missingToken:
                return "请先在设置中保存 DeepSeek API Token。"
            }
        }

        if let translationError = error as? DeepSeekTranslationError {
            switch translationError {
            case .emptyInput:
                return "请输入需要翻译的文本。"
            case .emptyOutput:
                return "DeepSeek 没有返回可用译文。"
            case .incompleteOutput:
                return "DeepSeek 输出被截断，请缩短文本后重试。"
            case .filteredOutput:
                return "DeepSeek 拒绝了该内容，请调整文本后重试。"
            case .insufficientSystemResource:
                return "DeepSeek 暂时资源不足，请稍后重试。"
            case .invalidResponse:
                return "DeepSeek 返回无效响应。"
            case .unauthorized:
                return "DeepSeek Token 无效或已过期。"
            case .httpStatus(let status):
                return "DeepSeek 请求失败：HTTP \(status)。"
            }
        }

        if let keychainError = error as? KeychainCredentialError {
            switch keychainError {
            case .unhandledStatus(let status):
                return "读取系统凭据失败：\(status)。"
            }
        }

        return "翻译请求失败，请检查网络后重试。"
    }
}

private enum TranslationState: Equatable {
    case idle
    case translating
    case translated(String)
    case failed(String)

    var isTranslating: Bool {
        self == .translating
    }

    var statusText: String {
        switch self {
        case .idle:
            return "等待翻译"
        case .translating:
            return "翻译中"
        case .translated:
            return "已翻译"
        case .failed:
            return "需要处理"
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
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
        #else
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        #endif
    }
}

private struct PromptedTextEditor: View {
    @Binding var text: String

    let prompt: String
    let minHeight: CGFloat
    var textStyle: TextInputTextStyle = .body
    var contentPadding = EdgeInsets()

    var body: some View {
        PlatformPromptedTextView(
            text: $text,
            prompt: prompt,
            textStyle: textStyle,
            contentPadding: contentPadding
        )
        .frame(minHeight: minHeight)
    }
}

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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

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

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.text = $text
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
        textView.inputAccessoryView = context.coordinator.makeDismissToolbar()
        context.coordinator.textView = textView

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
        weak var textView: UITextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func makeDismissToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(
                    title: "完成",
                    style: .done,
                    target: self,
                    action: #selector(dismissKeyboard)
                )
            ]
            toolbar.sizeToFit()
            return toolbar
        }

        @objc private func dismissKeyboard() {
            textView?.resignFirstResponder()
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

    var secondaryWidth: CGFloat? {
        switch self {
        case .commandBar:
            return 76
        case .macCommandBar:
            return 82
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

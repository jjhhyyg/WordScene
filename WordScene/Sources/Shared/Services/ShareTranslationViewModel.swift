import Foundation

@MainActor
final class ShareTranslationViewModel: ObservableObject {
    private enum ShareTranslationError: Error, Equatable {
        case missingToken
    }

    enum State: Equatable {
        case loading
        case ready(String)
        case translating(String)
        case translated(ShareExtensionHandoffRecord)
        case failed(String, sourceText: String?)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var didCopy = false
    @Published private(set) var didFavorite = false
    @Published private(set) var sourceLanguage: LanguageSelection = .auto
    @Published private(set) var targetLanguage: LanguageSelection

    private let extractor: SharedContentExtractor
    private let credentialStore: any CredentialStoring
    private let translationClient: any TranslationClienting
    private let handoffStore: ShareExtensionHandoffStore?
    private let preferencesStore: TranslationPreferencesStore
    private var lastTranslatedDirection: ShareLanguageDirection?

    init(
        extractor: SharedContentExtractor = SharedContentExtractor(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        translationClient: any TranslationClienting = DeepSeekTranslationClient(),
        handoffStore: ShareExtensionHandoffStore? = ShareExtensionHandoffStore(),
        preferencesStore: TranslationPreferencesStore = TranslationPreferencesStore()
    ) {
        self.extractor = extractor
        self.credentialStore = credentialStore
        self.translationClient = translationClient
        self.handoffStore = handoffStore
        self.preferencesStore = preferencesStore
        self.sourceLanguage = preferencesStore.shareSourceLanguage
        self.targetLanguage = preferencesStore.shareTargetLanguage
    }

    var shouldShowTranslateButton: Bool {
        !preferencesStore.isShareAutoTranslateEnabled
    }

    var canTranslateCurrentText: Bool {
        guard currentSourceText != nil else {
            return false
        }

        if case .translating = state {
            return false
        }

        return true
    }

    func load(providers: [NSItemProvider]) {
        Task {
            do {
                let extracted = try await extractor.extractText(from: providers)
                let sourceText = extracted.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sourceText.isEmpty else {
                    state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
                    return
                }
                state = .ready(sourceText)
                if preferencesStore.isShareAutoTranslateEnabled {
                    await translate(sourceText: sourceText)
                }
            } catch {
                state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
            }
        }
    }

    func retry() {
        switch state {
        case .ready(let sourceText), .translating(let sourceText):
            Task {
                await translate(sourceText: sourceText)
            }
        case .failed(_, let sourceText):
            guard let sourceText else { return }
            Task {
                await translate(sourceText: sourceText)
            }
        case .translated(let record):
            Task {
                await translate(sourceText: record.sourceText)
            }
        case .loading:
            break
        }
    }

    func translateCurrentText() async {
        guard let sourceText = currentSourceText else {
            state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
            return
        }

        await translate(sourceText: sourceText)
    }

    func updateSourceLanguage(_ language: LanguageSelection) {
        let source = LanguageSelection.sourceOptions.contains(language) ? language : .auto
        let direction = ShareLanguageDirection(source: source, target: targetLanguage).normalized()
        applyLanguageDirection(direction)
        translateIfDirectionChangedAfterPreviousTranslation()
    }

    func updateTargetLanguage(_ language: LanguageSelection) {
        let target = LanguageSelection.translationTargets.contains(language) ? language : .zh
        let direction = ShareLanguageDirection(source: sourceLanguage, target: target).normalized()
        applyLanguageDirection(direction)
        translateIfDirectionChangedAfterPreviousTranslation()
    }

    func translate(sourceText: String) async {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
            return
        }

        let direction = ShareLanguageDirection(source: sourceLanguage, target: targetLanguage).normalized()
        applyLanguageDirection(direction)
        preferencesStore.shareSourceLanguage = direction.source
        preferencesStore.shareTargetLanguage = direction.target
        didCopy = false
        didFavorite = false
        state = .translating(trimmed)

        do {
            guard let rawToken = try credentialStore.read(account: DeepSeekCredential.tokenAccount),
                  !rawToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ShareTranslationError.missingToken
            }

            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let translatedText = try await translationClient.translate(
                text: trimmed,
                source: direction.source,
                target: direction.target,
                apiToken: token
            )
            let record = ShareExtensionHandoffRecord(
                sourceText: trimmed,
                translatedText: translatedText,
                sourceLanguage: direction.source,
                targetLanguage: direction.target,
                isFavoritePending: false
            )
            try handoffStore?.save(record)
            try handoffStore?.appendPendingOperation(.history(record))
            lastTranslatedDirection = direction
            state = .translated(record)
        } catch ShareTranslationError.missingToken {
            state = .failed(String(localized: "请先在设置中保存 DeepSeek API Token。"), sourceText: trimmed)
        } catch {
            state = .failed(String(localized: "翻译失败，请稍后重试。"), sourceText: trimmed)
        }
    }

    func markCopied() {
        didCopy = true
    }

    func markFavorite() {
        guard case .translated(var record) = state else {
            return
        }

        record = ShareExtensionHandoffRecord(
            id: record.id,
            sourceText: record.sourceText,
            translatedText: record.translatedText,
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            isFavoritePending: true,
            createdAt: record.createdAt
        )

        do {
            try handoffStore?.save(record)
            try handoffStore?.appendPendingOperation(.favorite(record))
            didFavorite = true
            state = .translated(record)
        } catch {
            state = .failed(String(localized: "收藏失败，请打开译笺后重试。"), sourceText: record.sourceText)
        }
    }

    func openURL() -> URL? {
        guard case .translated(let record) = state else {
            return nil
        }

        return URL(
            string: "\(ShareExtensionConfiguration.urlScheme)://\(ShareExtensionConfiguration.handoffHost)?id=\(record.id.uuidString)"
        )
    }

    private var currentSourceText: String? {
        switch state {
        case .ready(let sourceText), .translating(let sourceText):
            return sourceText
        case .failed(_, let sourceText):
            return sourceText
        case .translated(let record):
            return record.sourceText
        case .loading:
            return nil
        }
    }

    private func applyLanguageDirection(_ direction: ShareLanguageDirection) {
        sourceLanguage = direction.source
        targetLanguage = direction.target
        preferencesStore.shareSourceLanguage = direction.source
        preferencesStore.shareTargetLanguage = direction.target
    }

    private func translateIfDirectionChangedAfterPreviousTranslation() {
        let direction = ShareLanguageDirection(source: sourceLanguage, target: targetLanguage).normalized()
        guard let lastTranslatedDirection,
              lastTranslatedDirection != direction,
              let sourceText = currentSourceText else {
            return
        }

        Task {
            await translate(sourceText: sourceText)
        }
    }
}

private struct ShareLanguageDirection: Equatable {
    let source: LanguageSelection
    let target: LanguageSelection

    func normalized() -> ShareLanguageDirection {
        guard LanguageSelection.targetOptions(excluding: source).contains(target) else {
            return ShareLanguageDirection(source: source, target: Self.defaultTarget(excluding: source))
        }

        return self
    }

    private static func defaultTarget(excluding source: LanguageSelection) -> LanguageSelection {
        let targets = LanguageSelection.targetOptions(excluding: source)
        return targets.first { $0 == .zh } ?? targets.first ?? .zh
    }
}

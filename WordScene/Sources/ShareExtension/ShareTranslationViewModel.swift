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
    @Published var targetLanguage: LanguageSelection = .zh

    private let extractor: SharedContentExtractor
    private let credentialStore: any CredentialStoring
    private let translationClient: any TranslationClienting
    private let handoffStore: ShareExtensionHandoffStore?

    init(
        extractor: SharedContentExtractor = SharedContentExtractor(),
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        translationClient: any TranslationClienting = DeepSeekTranslationClient(),
        handoffStore: ShareExtensionHandoffStore? = ShareExtensionHandoffStore()
    ) {
        self.extractor = extractor
        self.credentialStore = credentialStore
        self.translationClient = translationClient
        self.handoffStore = handoffStore
    }

    func load(providers: [NSItemProvider]) {
        Task {
            do {
                let extracted = try await extractor.extractText(from: providers)
                let sourceText = extracted.text
                state = .ready(sourceText)
                await translate(sourceText: sourceText)
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

    func translate(sourceText: String) async {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed(String(localized: "无法读取分享内容"), sourceText: nil)
            return
        }

        let detectedSource = TranslationLanguageDetector.detect(trimmed) ?? .auto
        sourceLanguage = detectedSource
        targetLanguage = normalizedTarget(for: detectedSource, currentTarget: targetLanguage)
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
                source: detectedSource,
                target: targetLanguage,
                apiToken: token
            )
            let record = ShareExtensionHandoffRecord(
                sourceText: trimmed,
                translatedText: translatedText,
                sourceLanguage: detectedSource,
                targetLanguage: targetLanguage,
                isFavoritePending: false
            )
            try handoffStore?.save(record)
            try handoffStore?.appendPendingOperation(.history(record))
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

    private func normalizedTarget(
        for source: LanguageSelection,
        currentTarget: LanguageSelection
    ) -> LanguageSelection {
        guard !LanguageSelection.targetOptions(excluding: source).contains(currentTarget) else {
            return currentTarget
        }

        if source == .zh || source == .zhHant {
            return .en
        }

        return .zh
    }
}

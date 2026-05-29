import Foundation

struct TranslationProviderRequest: Equatable, Sendable {
    let text: String
    let source: LanguageSelection
    let target: LanguageSelection
}

struct TranslationProviderCredential: Equatable, Sendable {
    let apiToken: String
}

struct TranslationLLMResult: Equatable, Sendable {
    let translatedText: String
}

protocol TranslationProvider: Sendable {
    func translate(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) async throws -> TranslationLLMResult
}

struct DeepSeekTranslationClient: Sendable {
    private let provider: any TranslationProvider

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-v4-flash"
    ) {
        provider = DeepSeekProvider(session: session, baseURL: baseURL, model: model)
    }

    init(provider: any TranslationProvider) {
        self.provider = provider
    }

    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) async throws -> String {
        try await provider.translate(
            TranslationProviderRequest(text: text, source: source, target: target),
            credential: TranslationProviderCredential(apiToken: apiToken)
        ).translatedText
    }
}

struct DeepSeekProvider: TranslationProvider {
    private let chatProvider: OpenAICompatibleChatProvider

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-v4-flash"
    ) {
        chatProvider = OpenAICompatibleChatProvider(
            session: session,
            baseURL: baseURL,
            model: model,
            systemPrompt: """
            You are a precise translation engine for a language learning app. Return only the translated text. Do not add explanations, alternatives, quotation marks, markdown, or notes.
            """
        )
    }

    func translate(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) async throws -> TranslationLLMResult {
        try await chatProvider.translate(request, credential: credential)
    }
}

struct OpenAICompatibleChatProvider: TranslationProvider {
    private let session: URLSession
    private let baseURL: URL
    private let model: String
    private let systemPrompt: String

    init(
        session: URLSession = .shared,
        baseURL: URL,
        model: String,
        systemPrompt: String
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
        self.systemPrompt = systemPrompt
    }

    func translate(
        _ providerRequest: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) async throws -> TranslationLLMResult {
        let trimmedText = providerRequest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw DeepSeekTranslationError.emptyInput
        }

        let endpoint = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: model,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(
                        role: "user",
                        content: userPrompt(
                            text: trimmedText,
                            source: providerRequest.source,
                            target: providerRequest.target
                        )
                    )
                ],
                thinking: .init(type: "disabled"),
                temperature: 0.2,
                stream: false
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekTranslationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
            let translatedText = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !translatedText.isEmpty else {
                throw DeepSeekTranslationError.emptyOutput
            }
            return TranslationLLMResult(translatedText: translatedText)
        case 401:
            throw DeepSeekTranslationError.unauthorized
        default:
            throw DeepSeekTranslationError.httpStatus(httpResponse.statusCode)
        }
    }

    private func userPrompt(text: String, source: LanguageSelection, target: LanguageSelection) -> String {
        """
        Source language: \(source.translationPromptName)
        Target language: \(target.translationPromptName)
        Text:
        \(text)
        """
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Thinking: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let thinking: Thinking
    let temperature: Double
    let stream: Bool
}

struct OpenAIChatCompletionResponse: Decodable, Equatable {
    struct Choice: Decodable, Equatable {
        struct Message: Decodable, Equatable {
            let role: String
            let content: String
        }

        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

typealias DeepSeekChatCompletionResponse = OpenAIChatCompletionResponse

enum DeepSeekTranslationError: Error, Equatable {
    case emptyInput
    case emptyOutput
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
}

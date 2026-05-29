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

protocol TranslationClienting: Sendable {
    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) async throws -> String
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

extension DeepSeekTranslationClient: TranslationClienting {}

struct DeepSeekProvider: TranslationProvider {
    private let chatProvider: OpenAICompatibleChatProvider

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-v4-flash"
    ) {
        #if DEBUG
        chatProvider = OpenAICompatibleChatProvider(
            session: session,
            baseURL: baseURL,
            model: model,
            systemPrompt: """
            You are a precise translation engine for a language learning app. Return json only. Use exactly this schema: {"translated_text":"..."}. Do not add explanations, alternatives, markdown, or notes.
            """,
            rawResponseRecorder: .userDefaultsBacked()
        )
        #else
        chatProvider = OpenAICompatibleChatProvider(
            session: session,
            baseURL: baseURL,
            model: model,
            systemPrompt: """
            You are a precise translation engine for a language learning app. Return json only. Use exactly this schema: {"translated_text":"..."}. Do not add explanations, alternatives, markdown, or notes.
            """
        )
        #endif
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
    #if DEBUG
    private let rawResponseRecorder: DebugRawAPIResponseRecorder?
    #endif

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
        #if DEBUG
        self.rawResponseRecorder = nil
        #endif
    }

    #if DEBUG
    init(
        session: URLSession = .shared,
        baseURL: URL,
        model: String,
        systemPrompt: String,
        rawResponseRecorder: DebugRawAPIResponseRecorder?
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
        self.systemPrompt = systemPrompt
        self.rawResponseRecorder = rawResponseRecorder
    }
    #endif

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
            chatCompletionRequest(
                text: trimmedText,
                source: providerRequest.source,
                target: providerRequest.target
            )
        )

        for attempt in 0..<2 {
            do {
                return try await perform(request)
            } catch DeepSeekTranslationError.emptyOutput where attempt == 0 {
                continue
            }
        }

        throw DeepSeekTranslationError.emptyOutput
    }

    private func chatCompletionRequest(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection
    ) -> OpenAIChatCompletionRequest {
        OpenAIChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(
                    role: "user",
                    content: userPrompt(text: text, source: source, target: target)
                )
            ],
            thinking: .init(type: "disabled"),
            responseFormat: .init(type: "json_object"),
            maxTokens: 1_200,
            temperature: 0.2,
            stream: false
        )
    }

    private func perform(_ request: URLRequest) async throws -> TranslationLLMResult {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekTranslationError.invalidResponse
        }
        #if DEBUG
        await rawResponseRecorder?.record(
            provider: model,
            endpoint: request.url ?? baseURL,
            statusCode: httpResponse.statusCode,
            bodyData: data
        )
        #endif

        switch httpResponse.statusCode {
        case 200:
            let decoded = try decodeResponse(from: data)
            let choice = try decoded.firstChoice()
            try validateFinishReason(choice.finishReason)
            return TranslationLLMResult(translatedText: try translatedText(from: choice.message.content))
        case 401:
            throw DeepSeekTranslationError.unauthorized
        default:
            throw DeepSeekTranslationError.httpStatus(httpResponse.statusCode)
        }
    }

    private func decodeResponse(from data: Data) throws -> OpenAIChatCompletionResponse {
        do {
            return try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw DeepSeekTranslationError.invalidResponse
        }
    }

    private func userPrompt(text: String, source: LanguageSelection, target: LanguageSelection) -> String {
        """
        Translate only the text field in the input json object below.
        Return json matching {"translated_text":"..."}.
        Input json:
        \(userPromptInputJSON(text: text, source: source, target: target))
        """
    }

    private func userPromptInputJSON(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection
    ) -> String {
        let payload = UserPromptInput(
            sourceLanguage: source.translationPromptName,
            targetLanguage: target.translationPromptName,
            text: text
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func validateFinishReason(_ finishReason: String?) throws {
        switch finishReason {
        case nil, "stop":
            return
        case "length":
            throw DeepSeekTranslationError.incompleteOutput
        case "content_filter":
            throw DeepSeekTranslationError.filteredOutput
        case "insufficient_system_resource":
            throw DeepSeekTranslationError.insufficientSystemResource
        default:
            throw DeepSeekTranslationError.invalidResponse
        }
    }

    private func translatedText(from content: String) throws -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw DeepSeekTranslationError.emptyOutput
        }

        guard let data = trimmedContent.data(using: .utf8) else {
            throw DeepSeekTranslationError.invalidResponse
        }

        do {
            let output = try JSONDecoder().decode(TranslationJSONOutput.self, from: data)
            let translatedText = output.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty else {
                throw DeepSeekTranslationError.emptyOutput
            }
            return translatedText
        } catch let error as DeepSeekTranslationError {
            throw error
        } catch {
            throw DeepSeekTranslationError.invalidResponse
        }
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

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let thinking: Thinking
    let responseFormat: ResponseFormat
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
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

    func firstChoice() throws -> Choice {
        guard let choice = choices.first else {
            throw DeepSeekTranslationError.invalidResponse
        }
        return choice
    }
}

typealias DeepSeekChatCompletionResponse = OpenAIChatCompletionResponse

private struct TranslationJSONOutput: Decodable {
    let translatedText: String

    enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
    }
}

private struct UserPromptInput: Encodable {
    let sourceLanguage: String
    let targetLanguage: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case text
    }
}

enum DeepSeekTranslationError: Error, Equatable {
    case emptyInput
    case emptyOutput
    case incompleteOutput
    case filteredOutput
    case insufficientSystemResource
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
}

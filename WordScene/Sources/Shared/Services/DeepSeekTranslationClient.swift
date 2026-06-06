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
    let detectedSourceLanguage: LanguageSelection
}

enum TranslationLLMStreamEvent: Equatable, Sendable {
    case partial(String)
    case completed(TranslationLLMResult)
}

protocol TranslationProvider: Sendable {
    func translate(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) async throws -> TranslationLLMResult

    func streamTranslation(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error>
}

protocol TranslationClienting: Sendable {
    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) async throws -> TranslationLLMResult

    func streamTranslation(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error>
}

extension TranslationProvider {
    func streamTranslation(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await translate(request, credential: credential)
                    continuation.yield(.partial(result.translatedText))
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension TranslationClienting {
    func streamTranslation(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await translate(text: text, source: source, target: target, apiToken: apiToken)
                    continuation.yield(.partial(result.translatedText))
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
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
    ) async throws -> TranslationLLMResult {
        try await provider.translate(
            TranslationProviderRequest(text: text, source: source, target: target),
            credential: TranslationProviderCredential(apiToken: apiToken)
        )
    }

    func streamTranslation(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error> {
        provider.streamTranslation(
            TranslationProviderRequest(text: text, source: source, target: target),
            credential: TranslationProviderCredential(apiToken: apiToken)
        )
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
            You are a precise translation engine for a language learning app. Return json only. Use exactly this schema: {"translated_text":"...","detected_source_language":"..."}. detected_source_language must be one of the allowed language codes from the user prompt. Do not add explanations, alternatives, markdown, or notes.
            """,
            rawResponseRecorder: .userDefaultsBacked()
        )
        #else
        chatProvider = OpenAICompatibleChatProvider(
            session: session,
            baseURL: baseURL,
            model: model,
            systemPrompt: """
            You are a precise translation engine for a language learning app. Return json only. Use exactly this schema: {"translated_text":"...","detected_source_language":"..."}. detected_source_language must be one of the allowed language codes from the user prompt. Do not add explanations, alternatives, markdown, or notes.
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

    func streamTranslation(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error> {
        chatProvider.streamTranslation(request, credential: credential)
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
        let token = credential.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        for attempt in 0..<2 {
            do {
                let result = try await withTranslationTimeout(seconds: 10) {
                    try await streamTranslationResult(providerRequest, credential: TranslationProviderCredential(apiToken: token)) { _ in }
                }
                return result
            } catch DeepSeekTranslationError.emptyOutput where attempt == 0 {
                continue
            }
        }

        throw DeepSeekTranslationError.emptyOutput
    }

    func streamTranslation(
        _ providerRequest: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await withTranslationTimeout(seconds: 10) {
                        try await streamTranslationResult(providerRequest, credential: credential) { partial in
                            continuation.yield(.partial(partial))
                        }
                    }
                    if result.translatedText.isEmpty {
                        throw DeepSeekTranslationError.emptyOutput
                    }
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: normalizedTimeoutError(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
            stream: true
        )
    }

    private func streamTranslationResult(
        _ providerRequest: TranslationProviderRequest,
        credential: TranslationProviderCredential,
        onPartialText: @escaping @Sendable (String) -> Void
    ) async throws -> TranslationLLMResult {
        let trimmedText = providerRequest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw DeepSeekTranslationError.emptyInput
        }

        let token = credential.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            chatCompletionRequest(
                text: trimmedText,
                source: providerRequest.source,
                target: providerRequest.target
            )
        )

        var accumulatedContent = ""
        var dataBuffer = Data()
        #if DEBUG
        var rawResponseData = Data()
        #endif
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekTranslationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw DeepSeekTranslationError.unauthorized
            }
            throw DeepSeekTranslationError.httpStatus(httpResponse.statusCode)
        }

        do {
            for try await byte in bytes {
                dataBuffer.append(byte)
                #if DEBUG
                rawResponseData.append(byte)
                #endif
                if byte == 10 {
                    let lineData = dataBuffer
                    dataBuffer.removeAll(keepingCapacity: true)
                    guard let line = String(data: lineData, encoding: .utf8) else {
                        throw DeepSeekTranslationError.invalidResponse
                    }
                    try consumeStreamLine(line, accumulatedContent: &accumulatedContent, onPartialText: onPartialText)
                }
            }
        } catch {
            throw normalizedTimeoutError(error)
        }

        if !dataBuffer.isEmpty {
            guard let line = String(data: dataBuffer, encoding: .utf8) else {
                throw DeepSeekTranslationError.invalidResponse
            }
            try consumeStreamLine(line, accumulatedContent: &accumulatedContent, onPartialText: onPartialText)
        }

        #if DEBUG
        await rawResponseRecorder?.record(
            provider: model,
            endpoint: request.url ?? baseURL,
            statusCode: httpResponse.statusCode,
            bodyData: rawResponseData
        )
        #endif

        return try translationResult(from: accumulatedContent)
    }

    private func consumeStreamLine(
        _ line: String,
        accumulatedContent: inout String,
        onPartialText: @escaping @Sendable (String) -> Void
    ) throws {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("data:") else {
            return
        }

        let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard payload != "[DONE]" else {
            return
        }

        guard let data = payload.data(using: .utf8) else {
            throw DeepSeekTranslationError.invalidResponse
        }
        let chunk = try decodeStreamChunk(from: data)
        let choice = try chunk.firstChoice()
        try validateFinishReason(choice.finishReason)
        if let content = choice.delta.content {
            accumulatedContent += content
            if let result = try? translationResult(from: accumulatedContent) {
                onPartialText(result.translatedText)
            } else if let partial = partialTranslatedText(from: accumulatedContent), !partial.isEmpty {
                onPartialText(partial)
            }
        }
    }

    private func decodeResponse(from data: Data) throws -> OpenAIChatCompletionResponse {
        do {
            return try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw DeepSeekTranslationError.invalidResponse
        }
    }

    private func decodeStreamChunk(from data: Data) throws -> OpenAIChatCompletionStreamChunk {
        do {
            return try JSONDecoder().decode(OpenAIChatCompletionStreamChunk.self, from: data)
        } catch {
            throw DeepSeekTranslationError.invalidResponse
        }
    }

    private func userPrompt(text: String, source: LanguageSelection, target: LanguageSelection) -> String {
        """
        Translate only the text field in the input json object below.
        When source_language is auto-detect, infer the source language from the full text yourself.
        Always produce text in target_language. Do not copy the input unchanged just because it contains words, product names, code terms, or technical terms already written in target_language.
        For mixed-language input, translate the natural-language meaning into target_language while preserving technical identifiers, command names, API names, file names, and product names when they are normally left untranslated.
        Return json matching {"translated_text":"...","detected_source_language":"..."}.
        Allowed detected_source_language values: \(Self.allowedDetectedSourceLanguageValues).
        detected_source_language must be the best source language code for the input text. Never return auto.
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

    private func translationResult(from content: String) throws -> TranslationLLMResult {
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
            guard let detectedSourceLanguage = output.validatedDetectedSourceLanguage else {
                throw DeepSeekTranslationError.invalidResponse
            }
            return TranslationLLMResult(
                translatedText: translatedText,
                detectedSourceLanguage: detectedSourceLanguage
            )
        } catch let error as DeepSeekTranslationError {
            throw error
        } catch {
            throw DeepSeekTranslationError.invalidResponse
        }
    }

    private static var allowedDetectedSourceLanguageValues: String {
        LanguageSelection.translationTargets.map(\.rawValue).joined(separator: ", ")
    }

    private func partialTranslatedText(from content: String) -> String? {
        let key = #""translated_text""#
        guard let keyRange = content.range(of: key),
              let colonRange = content.range(of: ":", range: keyRange.upperBound..<content.endIndex),
              let openingQuote = content[colonRange.upperBound...].firstIndex(of: "\"") else {
            return nil
        }

        var index = content.index(after: openingQuote)
        var result = ""
        var isEscaping = false
        while index < content.endIndex {
            let character = content[index]
            if isEscaping {
                switch character {
                case "\"", "\\", "/":
                    result.append(character)
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                default:
                    break
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                return result
            } else {
                result.append(character)
            }
            index = content.index(after: index)
        }
        return result
    }
}

private func withTranslationTimeout<T: Sendable>(
    seconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw DeepSeekTranslationError.timedOut
        }

        guard let result = try await group.next() else {
            throw DeepSeekTranslationError.timedOut
        }
        group.cancelAll()
        return result
    }
}

private func normalizedTimeoutError(_ error: Error) -> Error {
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return DeepSeekTranslationError.timedOut
    }
    return error
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

private struct OpenAIChatCompletionStreamChunk: Decodable, Equatable {
    struct Choice: Decodable, Equatable {
        struct Delta: Decodable, Equatable {
            let content: String?
        }

        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
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

private struct TranslationJSONOutput: Decodable {
    let translatedText: String
    let detectedSourceLanguage: String

    enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
        case detectedSourceLanguage = "detected_source_language"
    }

    var validatedDetectedSourceLanguage: LanguageSelection? {
        guard let language = LanguageSelection(rawValue: detectedSourceLanguage),
              LanguageSelection.translationTargets.contains(language) else {
            return nil
        }
        return language
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
    case timedOut
}

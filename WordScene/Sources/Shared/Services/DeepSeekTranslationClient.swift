import Foundation

struct DeepSeekTranslationClient {
    private let session: URLSession
    private let baseURL: URL
    private let model: String

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-v4-flash"
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
    }

    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw DeepSeekTranslationError.emptyInput
        }

        let endpoint = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekChatCompletionRequest(
                model: model,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(
                        role: "user",
                        content: userPrompt(text: trimmedText, source: source, target: target)
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
            let decoded = try JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data)
            let translatedText = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !translatedText.isEmpty else {
                throw DeepSeekTranslationError.emptyOutput
            }
            return translatedText
        case 401:
            throw DeepSeekTranslationError.unauthorized
        default:
            throw DeepSeekTranslationError.httpStatus(httpResponse.statusCode)
        }
    }

    private var systemPrompt: String {
        """
        You are a precise translation engine for a language learning app. Return only the translated text. Do not add explanations, alternatives, quotation marks, markdown, or notes.
        """
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

private struct DeepSeekChatCompletionRequest: Encodable {
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

struct DeepSeekChatCompletionResponse: Decodable, Equatable {
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

enum DeepSeekTranslationError: Error, Equatable {
    case emptyInput
    case emptyOutput
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
}

import XCTest
@testable import WordScene

final class DeepSeekTranslationResponseTests: XCTestCase {
    func testDecodesAssistantMessageContent() throws {
        let json = """
        {
          "choices": [
            {
              "index": 0,
              "finish_reason": "stop",
              "message": {
                "role": "assistant",
                "content": "你好，世界。"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: json)

        XCTAssertEqual(response.choices.first?.message.content, "你好，世界。")
        XCTAssertEqual(response.choices.first?.finishReason, "stop")
    }

    func testOpenAICompatibleProviderBuildsChatCompletionRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let requestCapture = RequestCapture()
        CapturingURLProtocol.handler = { request in
            await requestCapture.store(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "choices": [
                {
                  "index": 0,
                  "finish_reason": "stop",
                  "message": {
                    "role": "assistant",
                    "content": "你好"
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer {
            CapturingURLProtocol.handler = nil
        }

        let provider = OpenAICompatibleChatProvider(
            session: session,
            baseURL: URL(string: "https://example.test/v1")!,
            model: "adapter-model",
            systemPrompt: "System prompt"
        )

        let result = try await provider.translate(
            TranslationProviderRequest(text: "Hello", source: .en, target: .zh),
            credential: TranslationProviderCredential(apiToken: "test-token")
        )

        let capturedRequestValue = await requestCapture.recordedRequest()
        let capturedRequest = try XCTUnwrap(capturedRequestValue)
        XCTAssertEqual(result.translatedText, "你好")
        XCTAssertEqual(capturedRequest.url?.absoluteString, "https://example.test/v1/chat/completions")
        XCTAssertEqual(capturedRequest.httpMethod, "POST")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(Self.bodyData(for: capturedRequest))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "adapter-model")
        XCTAssertEqual(payload["stream"] as? Bool, false)
        XCTAssertEqual((payload["thinking"] as? [String: Any])?["type"] as? String, "disabled")

        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.first?["content"], "System prompt")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertTrue(messages.last?["content"]?.contains("Source language: English") == true)
        XCTAssertTrue(messages.last?["content"]?.contains("Target language: Chinese") == true)
        XCTAssertTrue(messages.last?["content"]?.contains("Hello") == true)
    }

    func testDeepSeekTranslationClientDelegatesToProvider() async throws {
        let provider = CapturingTranslationProvider(result: TranslationLLMResult(translatedText: "你好"))
        let client = DeepSeekTranslationClient(provider: provider)

        let result = try await client.translate(
            text: "Hello",
            source: .en,
            target: .zh,
            apiToken: "test-token"
        )

        XCTAssertEqual(result, "你好")
        let capturedRequest = await provider.recordedRequest()
        let capturedCredential = await provider.recordedCredential()
        XCTAssertEqual(capturedRequest, TranslationProviderRequest(text: "Hello", source: .en, target: .zh))
        XCTAssertEqual(capturedCredential, TranslationProviderCredential(apiToken: "test-token"))
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }
}

private actor RequestCapture {
    private var request: URLRequest?

    func store(_ request: URLRequest) {
        self.request = request
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}

private final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                guard let handler = Self.handler else {
                    throw DeepSeekTranslationError.invalidResponse
                }
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private actor CapturingTranslationProvider: TranslationProvider {
    private let result: TranslationLLMResult
    private var capturedRequest: TranslationProviderRequest?
    private var capturedCredential: TranslationProviderCredential?

    init(result: TranslationLLMResult) {
        self.result = result
    }

    func translate(
        _ request: TranslationProviderRequest,
        credential: TranslationProviderCredential
    ) async throws -> TranslationLLMResult {
        capturedRequest = request
        capturedCredential = credential
        return result
    }

    func recordedRequest() -> TranslationProviderRequest? {
        capturedRequest
    }

    func recordedCredential() -> TranslationProviderCredential? {
        capturedCredential
    }
}

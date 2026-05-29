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
}

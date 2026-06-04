import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import WordScene

final class SharedContentExtractorTests: XCTestCase {
    func testExtractsPlainText() async throws {
        let provider = NSItemProvider(item: "shared phrase" as NSString, typeIdentifier: UTType.plainText.identifier)

        let result = try await SharedContentExtractor().extractText(from: [provider])

        XCTAssertEqual(result.text, "shared phrase")
        XCTAssertNil(result.sourceURL)
    }

    func testExtractsURLWhenTextIsMissing() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)

        let result = try await SharedContentExtractor().extractText(from: [provider])

        XCTAssertEqual(result.text, "https://example.com/article")
        XCTAssertEqual(result.sourceURL, url)
    }

    func testPlainTextBeatsURL() async throws {
        let textProvider = NSItemProvider(item: "selected words" as NSString, typeIdentifier: UTType.plainText.identifier)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let urlProvider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)

        let result = try await SharedContentExtractor().extractText(from: [urlProvider, textProvider])

        XCTAssertEqual(result.text, "selected words")
        XCTAssertNil(result.sourceURL)
    }

    func testThrowsWhenNoReadableContentExists() async {
        do {
            _ = try await SharedContentExtractor().extractText(from: [])
            XCTFail("Expected unreadable content to throw")
        } catch SharedContentExtractorError.noReadableContent {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

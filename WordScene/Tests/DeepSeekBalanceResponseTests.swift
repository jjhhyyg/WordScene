import XCTest
@testable import WordScene

final class DeepSeekBalanceResponseTests: XCTestCase {
    func testDecodesAvailability() throws {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: json)

        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.balanceInfos.first?.currency, "CNY")
        XCTAssertEqual(response.balanceInfos.first?.totalBalance, "110.00")
    }

    func testClientRejectsAuthenticatedButUnavailableBalance() async throws {
        let session = URLSession(configuration: .deepSeekBalanceTest)
        DeepSeekBalanceURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = """
            {
              "is_available": false,
              "balance_infos": []
            }
            """.data(using: .utf8)!
            return (response, data)
        }
        defer {
            DeepSeekBalanceURLProtocol.handler = nil
        }
        let client = DeepSeekBalanceClient(session: session)

        do {
            _ = try await client.fetchBalance(apiToken: "  test-token\n")
            XCTFail("Expected unavailable balance to reject token validation.")
        } catch {
            XCTAssertEqual(error as? DeepSeekBalanceError, .unavailableBalance)
        }
    }
}

private extension URLSessionConfiguration {
    static var deepSeekBalanceTest: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeepSeekBalanceURLProtocol.self]
        return configuration
    }
}

private final class DeepSeekBalanceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw DeepSeekBalanceError.invalidResponse
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

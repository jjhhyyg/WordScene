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
}

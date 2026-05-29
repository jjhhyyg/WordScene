import Foundation

struct DeepSeekBalanceResponse: Decodable, Equatable {
    struct BalanceInfo: Decodable, Equatable {
        let currency: String
        let totalBalance: String
        let grantedBalance: String
        let toppedUpBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct DeepSeekBalanceClient {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.deepseek.com")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchBalance(apiToken: String) async throws -> DeepSeekBalanceResponse {
        let endpoint = baseURL.appending(path: "user/balance")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekBalanceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let response = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            guard response.isAvailable else {
                throw DeepSeekBalanceError.unavailableBalance
            }
            return response
        case 401:
            throw DeepSeekBalanceError.unauthorized
        default:
            throw DeepSeekBalanceError.httpStatus(httpResponse.statusCode)
        }
    }
}

enum DeepSeekBalanceError: Error, Equatable {
    case invalidResponse
    case unavailableBalance
    case unauthorized
    case httpStatus(Int)
}

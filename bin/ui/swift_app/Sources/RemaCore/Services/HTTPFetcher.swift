import Foundation

enum HTTPFetcher {
    // 有些網站看到非瀏覽器的 User-Agent 會擋或回不一樣的頁面，一律假裝成 Safari
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // attempts > 1 時，連線/逾時類錯誤會重試，每次失敗後等 retryDelay × 第幾次 秒。
    // 以前 Ruby 版的信望愛還特地只解析 IPv4 再連線（Net::HTTP 遇到 IPv6 路由不通會卡滿整個 open_timeout），
    // URLSession 本身有 Happy Eyeballs（IPv4/IPv6 同時試），不需要那個繞法
    static func get(_ url: URL, attempts: Int = 1, retryDelay: Double = 1) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw RemaError("HTTP \(http.statusCode)（\(url.host ?? url.absoluteString)）")
                }
                return data
            } catch let error as URLError where isRetryable(error) && attempt < attempts {
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            }
        }
    }

    private static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    static func url(_ base: String, query: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}

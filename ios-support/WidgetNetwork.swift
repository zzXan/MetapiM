import Foundation

// Prevent credentials being forwarded to another origin by HTTP redirects.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum WidgetNetwork {
    static func fetch(_ credentials: WidgetSession) async throws -> Snapshot {
        guard let base = URL(string: credentials.server),
              ["https", "http"].contains(base.scheme ?? ""), base.host != nil,
              base.user == nil, base.password == nil else { throw URLError(.badURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func get(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
            var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            if !query.isEmpty { parts.queryItems = query }
            guard let url = parts.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            return try JSONSerialization.jsonObject(with: data)
        }
        async let accountsResponse = get("api/accounts")
        async let logsResponse = get("api/stats/proxy-logs", query: [
            URLQueryItem(name: "view", value: "query"), URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "offset", value: "0")])
        let (a, l) = try await (accountsResponse, logsResponse)
        let accountObject = a as? [String: Any]
        let logObject = l as? [String: Any]
        guard let accounts = (a as? [[String: Any]]) ?? (accountObject?["accounts"] as? [[String: Any]]),
              let logs = (l as? [[String: Any]]) ?? ((logObject?["items"] ?? logObject?["logs"]) as? [[String: Any]]) else {
            throw URLError(.cannotParseResponse)
        }
        var balances: [String: (Int, Double)] = [:]
        for row in accounts {
            guard let site = row["site"] as? [String: Any],
                  let name = site["name"] as? String, !name.isEmpty else { continue }
            let previous = balances[name]
            let id = (row["id"] as? NSNumber)?.intValue ?? 0
            let previousID: Int = previous?.0 ?? id
            let previousBalance: Double = previous?.1 ?? 0.0
            let rowBalance: Double = (row["balance"] as? NSNumber)?.doubleValue ?? 0.0
            balances[name] = (min(previousID, id), previousBalance + rowBalance)
        }
        var ranked: [Snapshot.Balance] = []
        for (name, value) in balances {
            let balance = Snapshot.Balance(id: value.0, name: name, balance: value.1)
            ranked.append(balance)
        }
        ranked.sort { (left: Snapshot.Balance, right: Snapshot.Balance) -> Bool in
            if left.balance != right.balance { return left.balance > right.balance }
            return left.name.lowercased() < right.name.lowercased()
        }
        // The API orders createdAt descending, then id descending.
        let calls = logs.map { row -> Snapshot.Call in
            let prompt = (row["promptTokens"] as? NSNumber)?.intValue ?? 0
            let read = (row["cacheReadTokens"] as? NSNumber)?.intValue
            let creation = (row["cacheCreationTokens"] as? NSNumber)?.intValue ?? 0
            let cache = (read ?? 0) + creation
            let input = cache > prompt ? prompt + cache : prompt
            let site = row["siteName"] as? String ?? ""
            let model = row["modelRequested"] as? String ?? ""
            return Snapshot.Call(id: (row["id"] as? NSNumber)?.intValue ?? 0,
                vendor: !site.isEmpty ? site : (!model.isEmpty ? model : "未知供应商"),
                inputTokens: input, outputTokens: (row["completionTokens"] as? NSNumber)?.intValue ?? 0,
                cacheHitRate: read.flatMap { input > 0 ? min(1, max(0, Double($0) / Double(input))) : nil },
                estimatedCost: (row["estimatedCost"] as? NSNumber)?.doubleValue)
        }
        return Snapshot(generatedAt: ISO8601DateFormatter().string(from: Date()), balances: ranked, recentCalls: calls)
    }
}

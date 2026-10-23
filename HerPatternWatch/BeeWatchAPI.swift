import Foundation

struct BeeWatchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct BeeWatchTask: Identifiable, Hashable {
    let id: String
    let text: String
}

actor BeeWatchAPI {
    static let shared = BeeWatchAPI()
    private let base = URL(string: "https://api.developer.bee.amazon.dev")!
    private let tokenAccount = "bee-developer-token"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func hasToken() -> Bool {
        WatchSecureStore.read(account: tokenAccount) != nil
    }

    func connect(token: String) async throws {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 2048 else {
            throw BeeWatchError(message: "Enter a valid Bee developer token.")
        }
        _ = try await request("/v1/me", token: clean)
        try WatchSecureStore.save(Data(clean.utf8), account: tokenAccount)
    }

    func disconnect() {
        WatchSecureStore.clear(account: tokenAccount)
    }

    func tasks() async throws -> [BeeWatchTask] {
        try await tasks(token: savedToken())
    }

    func createTask(text: String) async throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 240 else {
            throw BeeWatchError(message: "Task text must be between 1 and 240 characters.")
        }
        _ = try await request("/v1/todos", method: "POST", token: savedToken(), payload: ["text": clean])
    }

    private func savedToken() throws -> String {
        guard let data = WatchSecureStore.read(account: tokenAccount),
              let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw BeeWatchError(message: "Connect Bee on this watch first.")
        }
        return token
    }

    private func tasks(token: String) async throws -> [BeeWatchTask] {
        let json = try await request("/v1/todos", token: token)
        let rows: [[String: Any]]
        if let array = json as? [[String: Any]] {
            rows = array
        } else if let object = json as? [String: Any],
                  let array = (object["todos"] as? [[String: Any]])
                    ?? (object["items"] as? [[String: Any]])
                    ?? (object["data"] as? [[String: Any]]) {
            rows = array
        } else {
            throw BeeWatchError(message: "Bee returned an unexpected task format.")
        }

        return rows.prefix(20).compactMap { row in
            guard let rawID = row["id"], let text = row["text"] as? String else { return nil }
            let id = String(describing: rawID)
            guard id.range(of: #"^[A-Za-z0-9_.:-]{1,120}$"#, options: .regularExpression) != nil,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return BeeWatchTask(id: id, text: String(text.prefix(240)))
        }
    }

    private func request(
        _ path: String,
        method: String = "GET",
        token: String,
        payload: [String: Any]? = nil
    ) async throws -> Any {
        var request = URLRequest(url: base.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 20
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw BeeWatchError(message: "Bee request failed. Check your token and connection.")
        }
        if data.isEmpty || http.statusCode == 204 { return [:] as [String: Any] }
        return try JSONSerialization.jsonObject(with: data)
    }
}

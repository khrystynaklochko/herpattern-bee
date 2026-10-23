import Foundation

struct WatchAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct AuthResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let token_type: String
}

private struct WatchSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

/// Standalone watch authentication: signs into the same Supabase Auth provider
/// used by the HerPattern iPhone/web clients. The publishable key is public;
/// a service-role key must NEVER be embedded in a watch or phone app.
actor WatchAPI {
    static let shared = WatchAPI()
    private let sessionKey = "user-session"
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    private func setting(_ name: String) throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: name) as? String,
              !value.isEmpty, !value.contains("REPLACE_WITH"), !value.contains("$(") else {
            throw WatchAPIError(message: "Configure \(name) in the Watch target")
        }
        return value
    }

    private func settings() throws -> (api: URL, auth: URL, publishable: String, clientID: String) {
        let apiText = try setting("HPMobileAPIURL")
        let authText = try setting("HPSupabaseURL")
        let key = try setting("HPSupabasePublishableKey")
        let clientID = try setting("HPClientID")
        guard let api = URL(string: apiText), api.scheme == "https", api.host == "herpattern.space",
              api.path == "/api/public/mobile/v1",
              let auth = URL(string: authText), auth.scheme == "https",
              auth.host?.hasSuffix(".supabase.co") == true else {
            throw WatchAPIError(message: "Invalid first-party HTTPS configuration")
        }
        return (api, auth, key, clientID)
    }

    func hasSession() -> Bool {
        WatchSecureStore.read(account: sessionKey) != nil
    }

    private func readSession() throws -> WatchSession {
        guard let data = WatchSecureStore.read(account: sessionKey),
              let auth = try? JSONDecoder().decode(WatchSession.self, from: data) else {
            throw WatchAPIError(message: "Sign in to HerPattern on the watch")
        }
        return auth
    }

    private func save(_ auth: AuthResponse) throws {
        guard auth.token_type.lowercased() == "bearer", !auth.access_token.isEmpty,
              !auth.refresh_token.isEmpty, auth.expires_in > 0 else {
            throw WatchAPIError(message: "Authentication service returned an invalid session")
        }
        let value = WatchSession(accessToken: auth.access_token,
                                 refreshToken: auth.refresh_token,
                                 expiresAt: Date().addingTimeInterval(TimeInterval(auth.expires_in)))
        try WatchSecureStore.save(try JSONEncoder().encode(value), account: sessionKey)
    }

    private func authRequest(grant: String, payload: [String: String]) async throws -> AuthResponse {
        let config = try settings()
        guard let url = URL(string: config.auth.absoluteString + "/auth/v1/token?grant_type=" + grant) else {
            throw WatchAPIError(message: "Invalid authentication endpoint")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.publishable, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WatchAPIError(message: grant == "password" ?
                                "Sign-in failed. Check your details or account security settings." :
                                "Session expired. Please sign in again.")
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func signIn(email: String, password: String) async throws {
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.contains("@"), cleaned.count <= 254, !password.isEmpty else {
            throw WatchAPIError(message: "Enter your email and password")
        }
        // No password persists beyond this request. Refresh credentials remain in watch Keychain.
        let result = try await authRequest(grant: "password", payload: ["email": cleaned, "password": password])
        try save(result)
    }

    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        let existing = try readSession()
        if !forceRefresh && existing.expiresAt > Date().addingTimeInterval(90) { return existing.accessToken }
        do {
            let next = try await authRequest(grant: "refresh_token", payload: ["refresh_token": existing.refreshToken])
            try save(next)
            return next.access_token
        } catch {
            // Network failures must not silently destroy a valid offline session.
            if !forceRefresh && existing.expiresAt > Date() { return existing.accessToken }
            throw error
        }
    }

    func signOut() async {
        // Delete locally first, irrespective of remote connectivity.
        let previous = try? readSession()
        WatchSecureStore.clear(account: sessionKey)
        guard let previous, let config = try? settings(),
              let url = URL(string: config.auth.absoluteString + "/auth/v1/logout?scope=local") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.publishable, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(previous.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: req)
    }

    private func perform(path: String, method: String, token: String, payload: [String: Any]?) async throws -> (Data, Int) {
        let config = try settings()
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: config.api.absoluteString + path),
              url.host == config.api.host, url.scheme == "https" else {
            throw WatchAPIError(message: "Invalid API route")
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(config.clientID, forHTTPHeaderField: "X-Client-Id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let payload {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw WatchAPIError(message: "Backend unavailable") }
        return (data, http.statusCode)
    }

    func request(_ path: String, method: String = "GET", payload: [String: Any]? = nil) async throws -> Any {
        let token = try await accessToken()
        var (data, status) = try await perform(path: path, method: method, token: token, payload: payload)
        if status == 401 {
            let fresh = try await accessToken(forceRefresh: true)
            (data, status) = try await perform(path: path, method: method, token: fresh, payload: payload)
        }
        guard (200...299).contains(status) else {
            if status == 401 { throw WatchAPIError(message: "Sign in again to continue") }
            if status == 403 { throw WatchAPIError(message: "This account is not yet approved") }
            if status == 429 { throw WatchAPIError(message: "Too many requests. Try again later") }
            throw WatchAPIError(message: "Could not sync with HerPattern (\(status))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["data"] else {
            throw WatchAPIError(message: "Unexpected HerPattern API response")
        }
        return value
    }
}

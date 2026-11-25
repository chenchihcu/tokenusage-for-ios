import CryptoKit
import Foundation

/// What a sign-in leaves on the phone. Stored as JSON in the Keychain only.
struct Credential: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    /// True when the access token is about to expire and can be renewed.
    func needsRenewal(now: Date = Date()) -> Bool {
        guard refreshToken != nil, let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < 120
    }
}

enum CredentialStore {
    private static func key(_ provider: DirectProvider) -> String { "credential.\(provider.rawValue)" }

    static func load(_ provider: DirectProvider) -> Credential? {
        guard let text = Keychain.get(key(provider)), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    static func save(_ credential: Credential, for provider: DirectProvider) {
        guard let data = try? JSONEncoder().encode(credential), let text = String(data: data, encoding: .utf8) else { return }
        Keychain.set(text, for: key(provider))
    }

    /// Sign out: removes the sign-in and any manually pasted token.
    static func delete(_ provider: DirectProvider) {
        Keychain.set("", for: key(provider))
        Keychain.set("", for: provider.keychainKey)
    }
}

enum SignInError: LocalizedError, Equatable {
    case network
    case rejected(status: Int)
    case unexpectedResponse
    case expired
    case badCode

    var errorDescription: String? {
        switch self {
        case .network: return "無法連線，請檢查網路後再試。"
        case .rejected(let status): return "服務拒絕了這次登入（\(status)）。"
        case .unexpectedResponse: return "服務回應的格式無法辨識，可能已變更。"
        case .expired: return "登入逾時，請重新開始。"
        case .badCode: return "授權碼格式不正確，請從登入頁完整複製。"
        }
    }
}

/// Sign-in from the phone, using each vendor's own sign-in page.
/// The app never sees a password. None of these flows is a documented public API:
/// they follow what the vendors' command-line tools do, and can stop working.
enum SignInService {
    // Public client identifiers of the vendors' own CLIs (not secrets).
    static let claudeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let claudeRedirect = "https://console.anthropic.com/oauth/code/callback"
    static let claudeTokenURL = "https://console.anthropic.com/v1/oauth/token"
    static let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let codexIssuer = "https://auth.openai.com"

    // MARK: Claude Code — OAuth with PKCE; the vendor page shows a code to paste back.

    struct ClaudeAttempt: Equatable {
        var url: URL
        var verifier: String
        var state: String
    }

    static func claudeBegin() -> ClaudeAttempt {
        let verifier = randomURLSafe(bytes: 32)
        let state = randomURLSafe(bytes: 32)
        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: claudeClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: claudeRedirect),
            .init(name: "scope", value: "org:create_api_key user:profile user:inference"),
            .init(name: "code_challenge", value: challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return ClaudeAttempt(url: components.url!, verifier: verifier, state: state)
    }

    /// The page shows `code#state`; either that or the bare code is accepted.
    static func claudeFinish(pasted: String, attempt: ClaudeAttempt) async throws -> Credential {
        let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1)
        guard let code = parts.first, !code.isEmpty, !code.contains(" ") else { throw SignInError.badCode }
        let state = parts.count > 1 ? String(parts[1]) : attempt.state
        let (status, json) = try await postJSON(claudeTokenURL, [
            "grant_type": "authorization_code",
            "code": String(code),
            "state": state,
            "client_id": claudeClientID,
            "redirect_uri": claudeRedirect,
            "code_verifier": attempt.verifier,
        ])
        return try credential(status: status, json: json, keepingRefresh: nil)
    }

    // MARK: Codex — device code: the app shows a code, the person enters it on OpenAI's page.

    struct CodexAttempt: Equatable {
        var deviceAuthID: String
        var userCode: String
        var interval: TimeInterval
        var url: URL
    }

    static func codexBegin() async throws -> CodexAttempt {
        let (status, json) = try await postJSON("\(codexIssuer)/api/accounts/deviceauth/usercode",
                                                ["client_id": codexClientID])
        guard status == 200 else { throw SignInError.rejected(status: status) }
        guard let id = json["device_auth_id"] as? String,
              let code = (json["user_code"] ?? json["usercode"]) as? String else {
            throw SignInError.unexpectedResponse
        }
        let interval = max(number(json["interval"]) ?? 5, 3)
        return CodexAttempt(deviceAuthID: id, userCode: code, interval: interval,
                            url: URL(string: "\(codexIssuer)/codex/device")!)
    }

    /// Waits until the person approves on the vendor page, up to 15 minutes.
    static func codexFinish(_ attempt: CodexAttempt) async throws -> Credential {
        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(attempt.interval))
            let (status, json) = try await postJSON("\(codexIssuer)/api/accounts/deviceauth/token", [
                "device_auth_id": attempt.deviceAuthID,
                "user_code": attempt.userCode,
            ])
            if status == 403 || status == 404 { continue }   // not approved yet
            guard status == 200 else { throw SignInError.rejected(status: status) }
            guard let code = json["authorization_code"] as? String,
                  let verifier = json["code_verifier"] as? String else { throw SignInError.unexpectedResponse }
            let (tokenStatus, tokenJSON) = try await postForm("\(codexIssuer)/oauth/token", [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": "\(codexIssuer)/deviceauth/callback",
                "client_id": codexClientID,
                "code_verifier": verifier,
            ])
            return try credential(status: tokenStatus, json: tokenJSON, keepingRefresh: nil)
        }
        throw SignInError.expired
    }

    // MARK: Cursor — browser sign-in, then the app asks Cursor whether it completed.

    struct CursorAttempt: Equatable {
        var uuid: String
        var verifier: String
        var url: URL
    }

    static func cursorBegin() -> CursorAttempt {
        let verifier = randomURLSafe(bytes: 32)
        let uuid = UUID().uuidString.lowercased()
        var components = URLComponents(string: "https://cursor.com/loginDeepControl")!
        components.queryItems = [
            .init(name: "challenge", value: challenge(for: verifier)),
            .init(name: "uuid", value: uuid),
            .init(name: "mode", value: "login"),
        ]
        return CursorAttempt(uuid: uuid, verifier: verifier, url: components.url!)
    }

    static func cursorFinish(_ attempt: CursorAttempt) async throws -> Credential {
        let deadline = Date().addingTimeInterval(10 * 60)
        var components = URLComponents(string: "https://api2.cursor.sh/auth/poll")!
        components.queryItems = [.init(name: "uuid", value: attempt.uuid), .init(name: "verifier", value: attempt.verifier)]
        while Date() < deadline {
            try await Task.sleep(for: .seconds(3))
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 15
            let (status, json) = try await send(request)
            if status == 404 { continue }   // not signed in yet
            guard status == 200 else { throw SignInError.rejected(status: status) }
            guard let access = json["accessToken"] as? String, !access.isEmpty else { throw SignInError.unexpectedResponse }
            return Credential(accessToken: access, refreshToken: json["refreshToken"] as? String,
                              expiresAt: JWT.expiry(of: access))
        }
        throw SignInError.expired
    }

    // MARK: Renewal

    /// Renews an access token on the phone. Returns nil when this provider has no renewal here.
    static func renew(_ credential: Credential, for provider: DirectProvider) async throws -> Credential? {
        guard let refresh = credential.refreshToken else { return nil }
        switch provider {
        case .claude:
            let (status, json) = try await postJSON(claudeTokenURL, [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": claudeClientID,
            ])
            return try self.credential(status: status, json: json, keepingRefresh: refresh)
        case .codex:
            let (status, json) = try await postJSON("\(codexIssuer)/oauth/token", [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": codexClientID,
                "scope": "openid profile email",
            ])
            return try self.credential(status: status, json: json, keepingRefresh: refresh)
        case .cursor, .antigravity:
            return nil
        }
    }

    /// The token to use now, renewed first when it is about to expire.
    /// Falls back to a manually pasted token (advanced setting).
    static func validToken(for provider: DirectProvider) async -> String? {
        guard var credential = CredentialStore.load(provider) else { return Keychain.get(provider.keychainKey) }
        if credential.needsRenewal(), let renewed = try? await renew(credential, for: provider) {
            credential = renewed
            CredentialStore.save(renewed, for: provider)
        }
        return credential.accessToken
    }

    // MARK: Building blocks

    static func credential(status: Int, json: [String: Any], keepingRefresh old: String?) throws -> Credential {
        guard (200..<300).contains(status) else { throw SignInError.rejected(status: status) }
        guard let access = json["access_token"] as? String, !access.isEmpty else { throw SignInError.unexpectedResponse }
        var expires = number(json["expires_in"]).map { Date().addingTimeInterval($0) }
        if expires == nil { expires = JWT.expiry(of: access) }
        return Credential(accessToken: access, refreshToken: (json["refresh_token"] as? String) ?? old, expiresAt: expires)
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafe(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func postJSON(_ url: String, _ body: [String: Any]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private static func postForm(_ url: String, _ fields: [String: String]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> (Int, [String: Any]) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return (status, json ?? [:])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SignInError.network
        }
    }
}

/// Reads claims from a JSON Web Token without verifying it (display and expiry only).
enum JWT {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func expiry(of token: String) -> Date? {
        guard let exp = claims(token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    /// Cursor's session cookie needs the user id from the token: `auth0|user_x` → `user_x`.
    static func cursorUserID(of token: String) -> String? {
        guard let sub = claims(token)?["sub"] as? String else { return nil }
        return sub.split(separator: "|").last.map(String.init)
    }
}

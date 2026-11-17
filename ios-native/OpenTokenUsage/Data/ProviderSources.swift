import Foundation
import Security

/// Account tokens live in the Keychain, never in UserDefaults.
enum Keychain {
    private static let service = "com.chihfu.opentokenusage.tokens"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Providers the phone can ask directly, with the person's own account token.
/// None of these usage endpoints is officially documented; each parser is lenient.
enum DirectProvider: String, CaseIterable, Identifiable {
    case claude, codex, cursor

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var tokenTitle: String {
        switch self {
        case .claude: return "Claude 存取權杖"
        case .codex: return "Codex 存取權杖"
        case .cursor: return "Cursor 工作階段 Cookie"
        }
    }

    var tokenHelp: String {
        switch self {
        case .claude: return "電腦上 ~/.claude/.credentials.json 的 accessToken。"
        case .codex: return "電腦上 ~/.codex/auth.json 的 tokens.access_token。"
        case .cursor: return "瀏覽器登入 cursor.com 後，Cookie「WorkosCursorSessionToken」的值。"
        }
    }

    var keychainKey: String { "token.\(rawValue)" }
    var token: String? { Keychain.get(keychainKey) }

    func request(token: String) -> URLRequest {
        var request: URLRequest
        switch self {
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case .codex:
            request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let account = QuotaParser.chatGPTAccountID(fromJWT: token) {
                request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
        case .cursor:
            request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
            let name = "WorkosCursorSessionToken="
            let value = token.hasPrefix(name) ? String(token.dropFirst(name.count)) : token
            request.setValue(name + value, forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    func parse(_ data: Data, now: Date = Date()) -> ProviderQuota? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch self {
        case .claude: return QuotaParser.claude(json, now: now)
        case .codex: return QuotaParser.codex(json, now: now)
        case .cursor: return QuotaParser.cursor(json, now: now)
        }
    }
}

/// Turns each provider's raw usage JSON into the app's `ProviderQuota`.
enum QuotaParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func claude(_ json: [String: Any], now: Date) -> ProviderQuota? {
        let windows: [(key: String, id: String, label: String)] = [
            ("five_hour", "5h", "5 小時"),
            ("seven_day", "weekly", "每週"),
            ("seven_day_opus", "weekly_opus", "每週（Opus）"),
            ("seven_day_sonnet", "weekly_sonnet", "每週（Sonnet）"),
        ]
        let tiers = windows.compactMap { window -> QuotaTier? in
            guard let dict = json[window.key] as? [String: Any],
                  let used = number(dict["utilization"]) else { return nil }
            return tier(id: window.id, label: window.label, used: used, resetsAt: dict["resets_at"] as? String)
        }
        guard !tiers.isEmpty else { return nil }
        return make(.claude, plan: "訂閱方案", poolName: "Claude 用量", tiers: tiers, metrics: [], now: now)
    }

    static func codex(_ json: [String: Any], now: Date) -> ProviderQuota? {
        guard let limits = json["rate_limit"] as? [String: Any] else { return nil }
        let tiers = ["primary_window", "secondary_window"].compactMap { key -> QuotaTier? in
            guard let dict = limits[key] as? [String: Any],
                  let used = number(dict["used_percent"]) else { return nil }
            let seconds = number(dict["limit_window_seconds"]) ?? 0
            var reset: String?
            if let at = number(dict["reset_at"]) {
                reset = iso.string(from: Date(timeIntervalSince1970: at))
            } else if let after = number(dict["reset_after_seconds"]) {
                reset = iso.string(from: now.addingTimeInterval(after))
            }
            return tier(id: key, label: windowLabel(seconds: seconds), used: used, resetsAt: reset)
        }
        guard !tiers.isEmpty else { return nil }
        var metrics: [QuotaMetric] = []
        if let credits = json["credits"] as? [String: Any], let balance = credits["balance"] {
            metrics.append(QuotaMetric(label: "Credits", value: "\(balance)"))
        }
        let plan = (json["plan_type"] as? String)?.capitalized ?? "ChatGPT"
        return make(.codex, plan: plan, poolName: "Codex 用量", tiers: tiers, metrics: metrics, now: now)
    }

    static func cursor(_ json: [String: Any], now: Date) -> ProviderQuota? {
        let usage = json["individualUsage"] as? [String: Any]
        guard let plan = usage?["plan"] as? [String: Any] else { return nil }
        var total = number(plan["totalPercentUsed"])
        if total == nil, let used = number(plan["used"]), let limit = number(plan["limit"]), limit > 0 {
            total = used / limit * 100
        }
        guard let total else { return nil }
        let reset = json["billingCycleEnd"] as? String
        var tiers = [tier(id: "total", label: "總用量", used: total, resetsAt: reset)]
        if let auto = number(plan["autoPercentUsed"]) {
            tiers.append(tier(id: "auto", label: "Auto 用量", used: auto, resetsAt: reset))
        }
        if let api = number(plan["apiPercentUsed"]) {
            tiers.append(tier(id: "api", label: "API 用量", used: api, resetsAt: reset))
        }
        let planName = (json["membershipType"] as? String)?.capitalized ?? "Cursor"
        return make(.cursor, plan: planName, poolName: "Cursor 用量", tiers: tiers, metrics: [], now: now)
    }

    /// The ChatGPT account id is a claim inside the access token itself.
    static func chatGPTAccountID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    // MARK: - Building blocks

    static func tier(id: String, label: String, used: Double, resetsAt: String?) -> QuotaTier {
        let clamped = min(max(used, 0), 100)
        return QuotaTier(id: id, label: label, used: clamped, limit: 100, remaining: 100 - clamped,
                         resetsAt: resetsAt, resetDurationText: nil, isGoverning: nil)
    }

    static func make(_ provider: DirectProvider, plan: String, poolName: String,
                     tiers: [QuotaTier], metrics: [QuotaMetric], now: Date) -> ProviderQuota {
        var tiers = tiers
        let worst = tiers.indices.min { tiers[$0].remaining < tiers[$1].remaining }
        if let worst { tiers[worst].isGoverning = true }
        let remaining = worst.map { tiers[$0].remaining } ?? 100
        let reset = worst.flatMap { tiers[$0].resetsAt }
        let pool = TokenPool(id: "\(provider.rawValue)_main", name: poolName, description: nil,
                             effectiveRemaining: remaining, effectiveUsed: 100 - remaining,
                             primaryResetTime: reset, isCritical: remaining <= 5, tiers: tiers)
        return ProviderQuota(
            providerId: provider.rawValue, name: provider.name, planName: plan,
            totalQuota: 100, usedQuota: 100 - remaining, remainingPercent: remaining,
            resetTime: reset ?? "", status: remaining <= 5 ? "warning" : "active",
            tokenPoolsJson: encode([pool]), metricsJson: metrics.isEmpty ? nil : encode(metrics),
            fetchedAt: iso.string(from: now))
    }

    private static func windowLabel(seconds: Double) -> String {
        switch seconds {
        case 18_000: return "5 小時"
        case 604_800: return "每週"
        case 86_400: return "每日"
        case let s where s >= 86_400: return "\(Int(s / 86_400)) 天"
        case let s where s >= 3_600: return "\(Int(s / 3_600)) 小時"
        default: return "用量"
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Reads several tokens pasted at once, in the labelled text the Mac helper writes:
/// a label line ("Claude…", "Codex…", "Cursor…" / "Workos…") followed by the value line.
/// Also accepts a bare `WorkosCursorSessionToken=` line. Placeholder lines in
/// parentheses are skipped.
enum TokenImport {
    static func parse(_ text: String) -> [DirectProvider: String] {
        var found: [DirectProvider: String] = [:]
        var pending: DirectProvider?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("workoscursorsessiontoken=") {
                found[.cursor] = String(line.dropFirst("WorkosCursorSessionToken=".count))
                pending = nil
            } else if line.hasSuffix(":") {
                if lower.hasPrefix("claude") { pending = .claude }
                else if lower.hasPrefix("codex") { pending = .codex }
                else if lower.hasPrefix("cursor") || lower.hasPrefix("workos") { pending = .cursor }
                else { pending = nil }
            } else if let provider = pending {
                if !line.hasPrefix("("), !line.contains(" ") { found[provider] = line }
                pending = nil
            }
        }
        return found
    }
}

/// Bundled figures for checking layouts without any account (Settings → 示範資料).
enum SampleData {
    static func items(now: Date = Date()) -> [ProviderQuota] {
        func at(_ hours: Double) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(hours * 3600))
        }
        return [
            QuotaParser.make(.cursor, plan: "Pro", poolName: "Cursor 用量", tiers: [
                QuotaParser.tier(id: "total", label: "總用量", used: 100, resetsAt: at(90)),
                QuotaParser.tier(id: "auto", label: "Auto 用量", used: 100, resetsAt: at(90)),
                QuotaParser.tier(id: "api", label: "API 用量", used: 0, resetsAt: at(90)),
            ], metrics: [], now: now),
            QuotaParser.make(.claude, plan: "訂閱方案", poolName: "Claude 用量", tiers: [
                QuotaParser.tier(id: "5h", label: "5 小時", used: 42, resetsAt: at(2.5)),
                QuotaParser.tier(id: "weekly", label: "每週", used: 81, resetsAt: at(60)),
                QuotaParser.tier(id: "weekly_opus", label: "每週（Opus）", used: 12, resetsAt: at(60)),
            ], metrics: [], now: now),
            QuotaParser.make(.codex, plan: "Plus", poolName: "Codex 用量", tiers: [
                QuotaParser.tier(id: "primary_window", label: "5 小時", used: 8, resetsAt: at(4)),
                QuotaParser.tier(id: "secondary_window", label: "每週", used: 35, resetsAt: at(120)),
            ], metrics: [QuotaMetric(label: "Credits", value: "0")], now: now),
        ]
    }
}

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

    /// Fastest the app will ask this provider, whatever the refresh setting.
    /// Claude's usage endpoint answers 429 when polled often. Starting values; tune on device.
    var minimumInterval: TimeInterval {
        switch self {
        case .claude: return 300
        case .codex, .cursor: return 60
        }
    }

    var keychainKey: String { "token.\(rawValue)" }
    /// Signed in (or, as an advanced fallback, a manually pasted token is present).
    var token: String? { CredentialStore.load(self)?.accessToken ?? Keychain.get(keychainKey) }
    var isSignedIn: Bool { token != nil }

    /// How the vendor's sign-in works, in the person's words.
    var signInSummary: String {
        switch self {
        case .claude: return "會開啟 Claude 官方登入頁。登入後頁面會顯示一組授權碼，複製後回到這裡貼上。"
        case .codex: return "App 會顯示一組代碼，並開啟 OpenAI 官方頁面。在該頁登入並輸入代碼即可。"
        case .cursor: return "會開啟 Cursor 官方登入頁。登入並同意後，回到這裡會自動完成。"
        }
    }

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
            var value = token.hasPrefix(name) ? String(token.dropFirst(name.count)) : token
            // The cookie is "<user id>::<token>". A bare token from in-app sign-in gets the id added.
            if !value.contains("::"), !value.contains("%3A%3A"), let user = JWT.cursorUserID(of: value) {
                value = "\(user)%3A%3A\(value)"
            }
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

    /// Claude Code meters models separately. `five_hour` and `seven_day` limit every model;
    /// keys such as `seven_day_opus` or `seven_day_sonnet` are extra weekly limits for one model.
    /// Any other per-model key the vendor adds (`seven_day_<name>`) becomes its own pool too.
    static func claude(_ json: [String: Any], now: Date) -> ProviderQuota? {
        func window(_ key: String, id: String, label: String) -> QuotaTier? {
            guard let dict = json[key] as? [String: Any],
                  let used = number(dict["utilization"]) else { return nil }
            // Fixed by the vendor: `five_hour` is 5 hours, every `seven_day*` key is 7 days.
            let seconds: Double = key == "five_hour" ? 5 * 3600 : 7 * 86_400
            return tier(id: id, label: label, used: used, resetsAt: dict["resets_at"] as? String,
                        windowSeconds: seconds)
        }
        var pools: [PoolDraft] = []
        let shared = [window("five_hour", id: "5h", label: "5 小時"),
                      window("seven_day", id: "weekly", label: "每週")].compactMap { $0 }
        if !shared.isEmpty {
            pools.append(PoolDraft(id: "claude_all", name: "所有模型", description: "每個模型都計入這些限制。", tiers: shared))
        }
        let known = ["opus": "Opus", "sonnet": "Sonnet", "oauth_apps": "第三方 App", "cowork": "Cowork"]
        let modelKeys = json.keys.filter { $0.hasPrefix("seven_day_") }.sorted()
        for key in modelKeys {
            let suffix = String(key.dropFirst("seven_day_".count))
            let name = known[suffix] ?? suffix.replacingOccurrences(of: "_", with: " ").capitalized
            guard let weekly = window(key, id: "weekly_\(suffix)", label: "每週") else { continue }
            pools.append(PoolDraft(id: "claude_\(suffix)", name: name,
                                   description: "\(name) 另有的每週限制，同時受「所有模型」限制。",
                                   tiers: [weekly]))
        }
        guard !pools.isEmpty else { return nil }
        return make(.claude, plan: "訂閱方案", pools: pools, metrics: [], now: now)
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
            return tier(id: key, label: windowLabel(seconds: seconds), used: used, resetsAt: reset,
                        windowSeconds: seconds > 0 ? seconds : nil)
        }
        guard !tiers.isEmpty else { return nil }
        var metrics: [QuotaMetric] = []
        if let credits = json["credits"] as? [String: Any], let balance = credits["balance"] {
            metrics.append(QuotaMetric(label: "Credits", value: "\(balance)"))
        }
        let plan = (json["plan_type"] as? String)?.capitalized ?? "ChatGPT"
        return make(.codex, plan: plan, poolName: "Codex 用量", tiers: tiers, metrics: metrics, now: now)
    }

    /// Cursor's paid plans meter two pools separately: Auto + Composer, and API (models you
    /// pick by name). `totalPercentUsed` combines both, so it is shown but does not gate anything.
    static func cursor(_ json: [String: Any], now: Date) -> ProviderQuota? {
        let usage = json["individualUsage"] as? [String: Any]
        guard let plan = usage?["plan"] as? [String: Any] else { return nil }
        var total = number(plan["totalPercentUsed"])
        if total == nil, let used = number(plan["used"]), let limit = number(plan["limit"]), limit > 0 {
            total = used / limit * 100
        }
        let reset = json["billingCycleEnd"] as? String
        // The cycle length comes from the start date when sent; otherwise assume one month.
        var cycleSeconds: Double?
        var cycleIsEstimate: Bool?
        if let end = reset.flatMap(QuotaDate.parse) {
            if let start = (json["billingCycleStart"] as? String).flatMap(QuotaDate.parse), start < end {
                cycleSeconds = end.timeIntervalSince(start)
            } else if let start = Calendar.current.date(byAdding: .month, value: -1, to: end) {
                cycleSeconds = end.timeIntervalSince(start)
                cycleIsEstimate = true
            }
        }
        func cycleTier(id: String, used: Double) -> QuotaTier {
            var t = tier(id: id, label: "本期", used: used, resetsAt: reset, windowSeconds: cycleSeconds)
            t.windowIsEstimate = cycleIsEstimate
            return t
        }
        var pools: [PoolDraft] = []
        if let auto = number(plan["autoPercentUsed"]) {
            pools.append(PoolDraft(id: "cursor_auto", name: "Auto + Composer", description: "Auto 模式與 Composer 模型。",
                                   tiers: [cycleTier(id: "auto", used: auto)]))
        }
        if let api = number(plan["apiPercentUsed"]) {
            pools.append(PoolDraft(id: "cursor_api", name: "API 模型", description: "手動指定的模型，例如 Claude、GPT。",
                                   tiers: [cycleTier(id: "api", used: api)]))
        }
        var metrics: [QuotaMetric] = []
        if pools.isEmpty {
            // Older accounts report only the combined figure: that is then the one pool.
            guard let total else { return nil }
            pools.append(PoolDraft(id: "cursor_plan", name: "方案用量", description: nil,
                                   tiers: [cycleTier(id: "total", used: total)]))
        } else if let total {
            metrics.append(QuotaMetric(label: "方案總用量", used: min(max(total, 0), 100), limit: 100))
        }
        let planName = (json["membershipType"] as? String)?.capitalized ?? "Cursor"
        return make(.cursor, plan: planName, pools: pools, metrics: metrics, now: now)
    }

    /// The ChatGPT account id is a claim inside the access token itself.
    static func chatGPTAccountID(fromJWT token: String) -> String? {
        let auth = JWT.claims(token)?["https://api.openai.com/auth"] as? [String: Any]
        return auth?["chatgpt_account_id"] as? String
    }

    // MARK: - Building blocks

    static func tier(id: String, label: String, used: Double, resetsAt: String?,
                     windowSeconds: Double? = nil) -> QuotaTier {
        QuotaAssembly.tier(id: id, label: label, used: used, resetsAt: resetsAt, windowSeconds: windowSeconds)
    }

    typealias PoolDraft = QuotaAssembly.PoolDraft

    /// One pool (providers that meter every model together, such as Codex).
    static func make(_ provider: DirectProvider, plan: String, poolName: String,
                     tiers: [QuotaTier], metrics: [QuotaMetric], now: Date) -> ProviderQuota {
        make(provider, plan: plan,
             pools: [PoolDraft(id: "\(provider.rawValue)_main", name: poolName, description: nil, tiers: tiers)],
             metrics: metrics, now: now)
    }

    static func make(_ provider: DirectProvider, plan: String, pools drafts: [PoolDraft],
                     metrics: [QuotaMetric], now: Date) -> ProviderQuota {
        QuotaAssembly.make(id: provider.rawValue, name: provider.name, plan: plan, pools: drafts,
                           metrics: metrics, now: now)
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
    /// The same rows the widget gallery uses (Shared/SampleQuotas.swift).
    static func items(now: Date = Date()) -> [ProviderQuota] {
        SampleQuotas.items(now: now)
    }

    /// Eight weeks of made-up daily use for the charts. Never stored.
    static func history(now: Date = Date(), calendar: Calendar = .current) -> UsageHistory {
        let series: [(key: String, provider: String, pool: String, base: Double, swing: Double)] = [
            ("claude/claude_all", "Claude Code", "所有模型", 9, 4),
            ("claude/claude_opus", "Claude Code", "Opus", 3, 2),
            ("claude/claude_sonnet", "Claude Code", "Sonnet", 6, 3),
            ("codex/codex_main", "Codex", "Codex 用量", 7, 3),
            ("cursor/cursor_auto", "Cursor", "Auto + Composer", 4, 2),
            ("cursor/cursor_api", "Cursor", "API 模型", 2, 1.5),
        ]
        var history = UsageHistory()
        let today = calendar.startOfDay(for: now)
        for (s, line) in series.enumerated() {
            for offset in (0..<56).reversed() {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                // Deterministic wobble so the sample looks the same every launch.
                let wobble = sin(Double(offset * (s + 3)) * 0.9) * line.swing
                let value = max(0, line.base + wobble)
                history.days.append(UsageDay(day: day, key: line.key, providerName: line.provider,
                                             poolName: line.pool, consumed: (value * 10).rounded() / 10))
            }
        }
        return history
    }
}


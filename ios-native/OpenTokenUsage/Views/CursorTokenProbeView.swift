import SwiftUI
import UIKit

/// TEMPORARY (docs/spec-token-usage-codex-cursor.md §12, step P1). Remove before any release.
/// Sends Cursor's dashboard usage-events requests once with the Cursor login stored on this
/// phone and shows only the response's field names and per-model totals, so the owner can
/// report them back. No values other than token and cent counts are shown.
struct CursorTokenProbeView: View {
    @State private var running = false
    @State private var report = ""

    var body: some View {
        Form {
            Section {
                Button(running ? "測試中…" : "測試 Cursor Token 資料") {
                    Task { await run() }
                }
                .disabled(running)
            } footer: {
                Text("暫時的測試功能。只向 cursor.com 送出兩個讀取請求，畫面只顯示欄位名稱與各模型的 token、cents 合計，不顯示帳號資料。")
            }
            if !report.isEmpty {
                Section("結果") {
                    Text(report)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("複製結果") { UIPasteboard.general.string = report }
                }
            }
        }
        .navigationTitle("Cursor Token 測試")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    private func run() async {
        running = true
        defer { running = false }
        report = await CursorTokenProbe.run()
    }
}

enum CursorTokenProbe {
    static func run() async -> String {
        guard let token = DirectProvider.cursor.token, !token.isEmpty else {
            return "這支手機沒有 Cursor 登入。"
        }
        var lines: [String] = []
        let summaryRequest = DirectProvider.cursor.request(token: token)
        var start = Date().addingTimeInterval(-30 * 86_400)
        do {
            let (data, response) = try await URLSession.shared.data(for: summaryRequest)
            lines.append("usage-summary: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["billingCycleStart"] as? String, let date = QuotaDate.parse(text) {
                start = date
                lines.append("cycle start: \(text)")
            }
        } catch {
            lines.append("usage-summary: \(error.localizedDescription)")
        }
        let startMs = String(Int(start.timeIntervalSince1970 * 1000))
        let endMs = String(Int(Date().timeIntervalSince1970 * 1000))

        for (name, body) in [
            ("get-filtered-usage-events", ["teamId": 0, "startDate": startMs, "endDate": endMs, "page": 1, "pageSize": 100] as [String: Any]),
            ("get-aggregated-usage-events", ["teamId": -1, "startDate": startMs, "endDate": endMs] as [String: Any]),
        ] {
            lines.append("")
            var request = summaryRequest
            request.url = URL(string: "https://cursor.com/api/dashboard/\(name)")
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                lines.append("\(name): HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1), \(data.count) bytes")
                guard let json = try? JSONSerialization.jsonObject(with: data) else {
                    lines.append("not JSON")
                    continue
                }
                lines.append("shape: " + shape(json))
                let totals = perModel(json)
                if totals.isEmpty { lines.append("per model: none found") }
                for (model, sums) in totals.sorted(by: { $0.key < $1.key }) {
                    let parts = sums.sorted { $0.key < $1.key }.map { "\($0.key)=\(Int($0.value))" }
                    lines.append("• \(model): " + parts.joined(separator: " "))
                }
            } catch {
                lines.append("\(name): \(error.localizedDescription)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Keys and value types only; numbers are shown only for token and cent fields.
    static func shape(_ value: Any, depth: Int = 0) -> String {
        if let array = value as? [Any] {
            return array.isEmpty ? "[0]" : "[\(array.count)] " + shape(array[0], depth: depth + 1)
        }
        if let dict = value as? [String: Any], depth < 5 {
            let parts = dict.keys.sorted().map { key -> String in
                let v = dict[key]!
                if v is [Any] || v is [String: Any] { return "\(key): \(shape(v, depth: depth + 1))" }
                return isCount(key) ? "\(key)=\(v)" : "\(key): \(kind(v))"
            }
            return "{" + parts.joined(separator: ", ") + "}"
        }
        return kind(value)
    }

    /// Sums every token / cent number under each object that names a model.
    static func perModel(_ value: Any) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        func numbers(_ value: Any, into sums: inout [String: Double]) {
            if let dict = value as? [String: Any] {
                for (key, v) in dict {
                    if isCount(key), let n = number(v) { sums[key, default: 0] += n } else { numbers(v, into: &sums) }
                }
            } else if let array = value as? [Any] {
                for v in array { numbers(v, into: &sums) }
            }
        }
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let model = ["model", "modelIntent", "modelName"].lazy.compactMap({ dict[$0] as? String }).first {
                    var sums = out[model] ?? [:]
                    numbers(dict, into: &sums)
                    out[model] = sums
                } else {
                    dict.values.forEach(walk)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(value)
        return out
    }

    private static func isCount(_ key: String) -> Bool {
        let k = key.lowercased()
        return k.contains("token") || k.contains("cent")
    }

    private static func number(_ value: Any) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func kind(_ value: Any) -> String {
        switch value {
        case is String: return "string"
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number"
        case is NSNull: return "null"
        default: return "\(type(of: value))"
        }
    }
}

import Foundation

/// Shared formatting for token counts, estimated API costs, and billing periods.
enum TokenFormat {
    /// Compact 64-bit token formatting: `0`, `850`, `1.2K`, `12.3M`, `1.1B`.
    static func shortCount(_ count: Int64) -> String {
        let clamped = max(count, 0)
        if clamped < 1_000 { return "\(clamped)" }

        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K"),
        ]
        let value = Double(clamped)
        for (index, unit) in units.enumerated() where value >= unit.threshold {
            let scaled = (value / unit.threshold * 10).rounded() / 10
            if scaled >= 1_000, index > 0 {
                let higher = units[index - 1]
                let promoted = (value / higher.threshold * 10).rounded() / 10
                return trimDecimal(promoted) + higher.suffix
            }
            return trimDecimal(scaled) + unit.suffix
        }
        return "\(clamped)"
    }

    /// Full integer string for VoiceOver so assistive tech does not read `M` or `K` literally.
    static func spokenCount(_ count: Int64) -> String {
        max(count, 0).formatted(.number)
    }

    /// Estimated API cost from cents, e.g. `410` -> `≈ $4.10`.
    static func estimatedCost(cents: Double) -> String {
        let dollars = max(cents, 0) / 100.0
        return "≈ $" + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), dollars)
    }

    /// List row summary (TR-1): `本期 12.3M tokens · ≈ $4.10`.
    static func rowSummary(_ usage: TokenUsageSummary) -> String {
        let prefix = usage.isPartial == true ? "≥ " : ""
        let base = "本期 \(prefix)\(shortCount(usage.totalTokens)) tokens"
        if let cents = usage.totalCents {
            return "\(base) · \(estimatedCost(cents: cents))"
        }
        return base
    }

    /// VoiceOver summary with full numbers and currency wording.
    static func rowAccessibilityLabel(_ usage: TokenUsageSummary) -> String {
        let prefix = usage.isPartial == true ? "至少 " : ""
        let base = "本期\(prefix)\(spokenCount(usage.totalTokens)) tokens"
        if let cents = usage.totalCents {
            let dollars = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(cents, 0) / 100.0)
            return "\(base)，約 \(dollars) 美元"
        }
        return base
    }

    /// Detail period label: `11/3 – 12/3` or `最近 30 天`.
    static func periodText(_ usage: TokenUsageSummary, calendar: Calendar = .current) -> String {
        guard !usage.isFallbackPeriod,
              let start = usage.periodStartDate,
              let end = usage.periodEndDate else {
            return "最近 30 天"
        }
        let s = calendar.dateComponents([.month, .day], from: start)
        let e = calendar.dateComponents([.month, .day], from: end)
        guard let sm = s.month, let sd = s.day, let em = e.month, let ed = e.day else {
            return "最近 30 天"
        }
        return "\(sm)/\(sd) – \(em)/\(ed)"
    }

    private static func trimDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

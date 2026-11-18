import SwiftUI
import UIKit

// Pieces of the 額度 row shared by the app and the home-screen widget, so both read the same
// way (spec-widget-alignment.md, FR-W3, FR-W6).

/// Each separately metered model pool with what is left in it, so the row says which
/// models still work when one pool has run out ("Opus 0% · Sonnet 80%").
struct PoolSummary: View {
    let pools: [TokenPool]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // One pool per line, free to wrap, so a long name never widens the row.
                VStack(alignment: .leading, spacing: 2) { items(fixed: false) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { items(fixed: true) }
                    VStack(alignment: .leading, spacing: 2) { items(fixed: false) }
                }
            }
        }
        .font(.caption)
    }

    private func items(fixed: Bool) -> some View {
        ForEach(pools) { pool in
            Self.text(pool)
                .monospacedDigit()
                .fixedSize(horizontal: fixed, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }

    static let separator = " · "

    static func percent(_ pool: TokenPool) -> String {
        (pool.effectiveRemaining / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// 「Opus 88%」: the name in secondary, the figure in its level colour.
    static func text(_ pool: TokenPool) -> Text {
        let name = Text(pool.name).foregroundStyle(.secondary)
        let figure = Text(verbatim: percent(pool))
            .foregroundStyle(QuotaLevel(remaining: pool.effectiveRemaining).textTint)
        return Text("\(name) \(figure)")
    }

    /// Every pool on one line, joined by 「 · 」 (the widget has room for one line only).
    static func line(_ pools: [TokenPool]) -> Text {
        let sep = Text(verbatim: separator).foregroundStyle(.secondary)
        return pools.enumerated().reduce(Text(verbatim: "")) { line, item in
            item.offset == 0 ? Text("\(line)\(text(item.element))") : Text("\(line)\(sep)\(text(item.element))")
        }
    }

    /// The same line as plain text, for VoiceOver and tests.
    static func plainLine(_ pools: [TokenPool]) -> String {
        pools.map { "\($0.name) \(percent($0))" }.joined(separator: separator)
    }
}

struct ResetText: View {
    let date: Date

    var body: some View {
        Self.text(date)
    }

    static func text(_ date: Date) -> Text {
        date > Date()
            ? Text("\(date, style: .relative)後重置")
            : Text("重置時間已過 · \(date, format: .dateTime.month().day().hour().minute())")
    }
}

extension QuotaLevel {
    /// Fill colour for bars and gauges.
    var tint: Color {
        switch self {
        case .exhausted: return .red
        case .low: return .orange
        case .healthy: return .green
        }
    }

    /// Colour for figures and words drawn in the level colour. System green and orange are
    /// about 2.2:1 on white, so text uses darker shades in light mode (≥ 4.5:1 on white and
    /// on the grouped background); dark mode keeps the system colours, which already pass.
    var textTint: Color {
        switch self {
        case .exhausted: return .statusRed
        case .low: return .statusOrange
        case .healthy: return .statusGreen
        }
    }
}

extension Color {
    /// Status colours for text (see `QuotaLevel.textTint`).
    static let statusGreen = adaptive(light: 0x1F7A33, dark: .systemGreen)
    static let statusOrange = adaptive(light: 0xA85200, dark: .systemOrange)
    static let statusRed = adaptive(light: 0xC4281C, dark: .systemRed)

    private static func adaptive(light hex: UInt32, dark: UIColor) -> Color {
        let lightColor = UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                                 green: CGFloat((hex >> 8) & 0xFF) / 255,
                                 blue: CGFloat(hex & 0xFF) / 255,
                                 alpha: 1)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : lightColor })
    }
}

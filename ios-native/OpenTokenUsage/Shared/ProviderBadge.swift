import SwiftUI
import UIKit

/// Original badge per AI vendor (spec-vendor-badges-app-icon.md, FR-B1…FR-B7): its own colour
/// and its own symbol, so vendors are told apart at a glance and in grayscale. No vendor logo
/// is bundled; an owner-supplied `logo-<id>.png` still replaces the badge (FR-38 / FR-B5).
/// Shared by the app and the widget.
struct ProviderBadge: View {
    let id: String
    let name: String
    /// Side at the default text size; it grows with Dynamic Type so the symbol or logo is
    /// never clipped (FR-B2).
    var base: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// Below this side a symbol is too small to read, so the 2-letter code shows (FR-B4).
    static let codeThreshold: CGFloat = 20

    var body: some View {
        let side = base * scale
        let shape = RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
        let style = ProviderStyle.style(for: id, name: name)
        ZStack {
            shape.fill(style.color)
            if let logo = ProviderStyle.logo(for: id) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
            } else if side >= Self.codeThreshold, let symbol = style.symbol,
                      UIImage(systemName: symbol) != nil {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: side * 0.55, height: side * 0.55)
            } else {
                Text(style.code)
                    .font(.system(size: side * 0.42, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(side * 0.08)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay {
            if needsBorder {
                shape.strokeBorder(Color(uiColor: .separator), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    /// Keeps Codex's near-black badge visible on dark backgrounds, and every badge with
    /// Increase Contrast on.
    private var needsBorder: Bool {
        contrast == .increased || (id == "codex" && colorScheme == .dark)
    }
}

/// A vendor's badge and name side by side, for setting and sign-in rows.
struct VendorLabel: View {
    let id: String
    let name: String

    var body: some View {
        HStack(spacing: 10) {
            ProviderBadge(id: id, name: name, base: 26)
            Text(name)
        }
    }
}

enum ProviderStyle {
    struct Style: Equatable {
        /// sRGB, 0xRRGGBB.
        var hex: UInt32
        /// SF Symbols name; nil uses the code.
        var symbol: String?
        var code: String

        var color: Color {
            Color(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
        }
    }

    /// FR-B1. Every background carries white at ≥ 4.5:1; symbols differ in shape (FR-B3).
    static let known: [String: Style] = [
        "claude": Style(hex: 0xB5532F, symbol: "asterisk", code: "CC"),
        "codex": Style(hex: 0x1F1F1F, symbol: "chevron.left.forwardslash.chevron.right", code: "CX"),
        "cursor": Style(hex: 0x0A7A76, symbol: "cursorarrow", code: "CU"),
        "antigravity": Style(hex: 0x2F5FD6, symbol: "arrow.up.to.line", code: "AG"),
    ]

    /// The one vendor order used by the 額度 list and the widget (spec-widget-alignment.md FR-W1).
    /// Never sorted by remaining %.
    static let order = ["claude", "codex", "cursor", "antigravity"]

    static func vendorOrdered<T>(_ items: [T], id: (T) -> String) -> [T] {
        func rank(_ item: T) -> Int { order.firstIndex(of: id(item)) ?? order.count }
        return items.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Vendors without a definition: grey with the first two letters (FR-B6).
    static func style(for id: String, name: String) -> Style {
        if let style = known[id] { return style }
        let letters = name.filter { $0.isLetter }.prefix(2).uppercased()
        return Style(hex: 0x6B6B70, symbol: nil, code: letters.isEmpty ? "?" : letters)
    }

    /// Logo files the owner adds under Resources/Logos: logo-claude.png, logo-codex.png,
    /// logo-cursor.png, logo-antigravity.png (square PNG, at least 180 × 180 px).
    static func logo(for id: String) -> UIImage? {
        UIImage(named: "logo-\(id)")
    }
}

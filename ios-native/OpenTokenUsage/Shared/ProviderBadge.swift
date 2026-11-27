import SwiftUI
import UIKit

/// Original mark per company. The shape is recognisable; the artwork is not a vendor logo.
/// An owner-supplied `logo-<id>.png` still replaces the drawing.
/// Shared by the app and the widget.
struct ProviderBadge: View {
    let id: String
    let name: String
    /// Side at the default text size; it grows with Dynamic Type so the mark is never clipped.
    var base: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let side = base * scale
        let shape = RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
        let style = ProviderStyle.style(for: id, name: name)
        ZStack {
            shape.fill(style.background)
            if let logo = ProviderStyle.logo(for: id) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                mark(style, side: side)
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

    @ViewBuilder
    private func mark(_ style: ProviderStyle.Style, side: CGFloat) -> some View {
        switch style.mark {
        case .burst:
            BurstMark()
                .stroke(style.ink, style: StrokeStyle(lineWidth: side * 0.09, lineCap: .round))
                .padding(side * 0.2)
        case .knot:
            KnotMark()
                .fill(style.ink)
                .padding(side * 0.18)
        case .pointer:
            PointerMark()
                .fill(style.ink)
                .padding(side * 0.16)
        case .quadrants:
            QuadrantMark()
                .padding(side * 0.1)
        case .letters(let text):
            Text(text)
                .font(.system(size: side * 0.42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(style.ink)
                .padding(side * 0.08)
        }
    }

    /// Near-black on a dark list, and near-white on a light list, need a hairline.
    private var needsBorder: Bool {
        contrast == .increased
            || (id == "codex" && colorScheme == .dark)
            || (id == "cursor" && colorScheme == .light)
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
    /// One drawing. The four companies never fall back to a two-letter code.
    enum Mark: Equatable {
        case burst, knot, pointer, quadrants
        case letters(String)
    }

    struct Style: Equatable {
        var mark: Mark
        /// sRGB background, 0xRRGGBB. Quadrants paint over most of it.
        var hex: UInt32
        /// sRGB ink for burst, knot, pointer and letters.
        var inkHex: UInt32

        var background: Color { Self.color(hex) }
        var ink: Color { Self.color(inkHex) }

        static func color(_ hex: UInt32) -> Color {
            Color(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
        }
    }

    /// Blue, red, yellow, green, clockwise from the top.
    static let quadrantHexes: [UInt32] = [0x4285F4, 0xEA4335, 0xF6C400, 0x34A853]

    static let known: [String: Style] = [
        "claude": Style(mark: .burst, hex: 0xC2410C, inkHex: 0xFFFFFF),
        "codex": Style(mark: .knot, hex: 0x1F1F1F, inkHex: 0xFFFFFF),
        "cursor": Style(mark: .pointer, hex: 0xF5F5F7, inkHex: 0x1A1A1A),
        "antigravity": Style(mark: .quadrants, hex: 0xF5F5F7, inkHex: 0x1A1A1A),
    ]

    /// The one vendor order used by the 額度 list and the widget.
    /// Never sorted by remaining %.
    static let order = ["claude", "codex", "cursor", "antigravity"]

    static func vendorOrdered<T>(_ items: [T], id: (T) -> String) -> [T] {
        func rank(_ item: T) -> Int { order.firstIndex(of: id(item)) ?? order.count }
        return items.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Vendors without a definition: grey with the first two letters.
    static func style(for id: String, name: String) -> Style {
        if let style = known[id] { return style }
        let letters = name.filter(\.isLetter).prefix(2).uppercased()
        return Style(mark: .letters(letters.isEmpty ? "?" : letters), hex: 0x6B6B70, inkHex: 0xFFFFFF)
    }

    /// Logo files the owner adds under Resources/Logos: logo-claude.png, logo-codex.png,
    /// logo-cursor.png, logo-antigravity.png (square PNG, at least 180 × 180 px).
    static func logo(for id: String) -> UIImage? {
        UIImage(named: "logo-\(id)")
    }
}

/// Eight rays with an empty centre.
private struct BurstMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.28
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * .pi * 2 - .pi / 2
            let dx = cos(angle)
            let dy = sin(angle)
            path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            path.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        }
        return path
    }
}

/// Six overlapping discs, a knot rather than a code bracket.
private struct KnotMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.22
        let orbit = radius * 0.95
        for index in 0..<6 {
            let angle = CGFloat(index) / 6 * .pi * 2
            let origin = CGPoint(x: center.x + cos(angle) * orbit - radius,
                                 y: center.y + sin(angle) * orbit - radius)
            path.addEllipse(in: CGRect(x: origin.x, y: origin.y, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

/// A pointer aimed up and to the left.
private struct PointerMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let x = rect.minX + (rect.width - s) / 2 + s * 0.18
        let y = rect.minY + (rect.height - s) / 2 + s * 0.14
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: y + s * 0.66))
        path.addLine(to: CGPoint(x: x + s * 0.16, y: y + s * 0.48))
        path.addLine(to: CGPoint(x: x + s * 0.36, y: y + s * 0.68))
        path.addLine(to: CGPoint(x: x + s * 0.48, y: y + s * 0.56))
        path.addLine(to: CGPoint(x: x + s * 0.28, y: y + s * 0.36))
        path.addLine(to: CGPoint(x: x + s * 0.50, y: y + s * 0.22))
        path.closeSubpath()
        return path
    }
}

/// A circle split in four. No letter.
private struct QuadrantMark: View {
    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (index, hex) in ProviderStyle.quadrantHexes.enumerated() {
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(Double(index) * 90 - 90),
                            endAngle: .degrees(Double(index + 1) * 90 - 90),
                            clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(ProviderStyle.Style.color(hex)))
            }
        }
    }
}

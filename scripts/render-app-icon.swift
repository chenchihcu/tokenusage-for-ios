// Renders the app icon SVGs in docs/icon/ to the 1024 × 1024 PNGs in AppIcon.appiconset
// (spec-vendor-badges-app-icon.md, FR-I4). macOS only; uses AppKit's SVG support.
//
//   swift scripts/render-app-icon.swift
//
// Light and tinted are written opaque (no alpha), as the App Store requires; dark keeps its
// transparent background so iOS supplies the dark backdrop.
import AppKit
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appending(path: "docs/icon")
let target = root.appending(path: "ios-native/OpenTokenUsage/Resources/Assets.xcassets/AppIcon.appiconset")

let jobs: [(svg: String, png: String, opaque: Bool)] = [
    ("app-icon.svg", "AppIcon-1024.png", true),
    ("app-icon-dark.svg", "AppIcon-1024-dark.png", false),
    ("app-icon-tinted.svg", "AppIcon-1024-tinted.png", true),
]

for job in jobs {
    guard let image = NSImage(contentsOf: source.appending(path: job.svg)) else {
        fatalError("Could not read \(job.svg)")
    }
    let side = 1024
    let alpha: CGImageAlphaInfo = job.opaque ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
    if job.opaque {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    let url = target.appending(path: job.png) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(job.png)") }
    print("wrote \(job.png)")
}

// make-mac-icons.swift -- the macOS-style app and document icons (native-look).
//
// Run by Mac/scripts/make-mac-icons.sh as
//
//     swift Mac/scripts/make-mac-icons.swift <repo>
//
// Draws everything with Core Graphics -- no SF Symbols (Apple's licence keeps them out of app
// icons) and no third-party art:
//
//   * the app icon: a light macOS squircle with the archive icons' grey zipper and "7-Zip" in blue
//     (the zipper alone at 16 and 32 px);
//   * one document icon per format: macOS's own archive icon (`UTType.archive`, the grey sheet with
//     the zipper that Finder shows for compressed files) with the extension under the zipper in
//     the grey, size and place of the label on macOS's ZIP icon (measured: caps 84 of 1024 units,
//     baseline 137 above the bottom, #B6B6B6). No label at 16 and 32 px, as on macOS's own icons.
//     The archive icon is taken from the Mac the script runs on, so the result follows that
//     macOS version; it is Apple's artwork -- fine for your own build, not for redistribution.
//
// Writes Mac/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png, Mac/Resources/Icons/
// doc-<name>.icns (through `iconutil`), Mac/Resources/Assets.xcassets/doc-<name>.imageset/
// doc-<name>_256.png / _512.png, and the contact sheet Mac/build/screenshots/icons-mac-sheet.png.

import AppKit
import Foundation

let repo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let fm = FileManager.default

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Renders `draw` (in a 1024-unit square, origin bottom-left) into a `pixels`-square PNG.
func render(_ pixels: Int, _ draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let srgb = rep.retagging(with: .sRGB) ?? rep
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: srgb)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    draw(CGFloat(pixels))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return srgb.representation(using: .png, properties: [:])!
}

// MARK: - app icon

/// macOS-style zipper (as on the system's archive icon): a capsule pull with a round hole, then
/// alternating rounded teeth under it. `k` scales the 1024-unit design.
func drawSystemZipper(cx: CGFloat, top: CGFloat, scale k: CGFloat, color: NSColor, hole: NSColor, teeth: Int) {
    let pullW = 150 * k, pullH = 300 * k
    let pull = NSRect(x: cx - pullW / 2, y: top - pullH, width: pullW, height: pullH)
    color.setFill()
    NSBezierPath(roundedRect: pull, xRadius: pullW / 2, yRadius: pullW / 2).fill()
    hole.setFill()
    let d = pullW * 0.42
    NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: pull.minY + pullW * 0.32, width: d, height: d)).fill()
    color.setFill()
    let tw = 170 * k, th = 48 * k
    var y = pull.minY - 60 * k
    for i in 0..<teeth {
        let x = i % 2 == 0 ? cx - tw * 0.62 : cx - tw * 0.38
        NSBezierPath(roundedRect: NSRect(x: x, y: y - th, width: tw, height: th), xRadius: th / 2, yRadius: th / 2).fill()
        y -= th * 1.45
    }
}

/// The app icon (the user's choice, variant A): a light tile like Apple's utilities, the grey
/// zipper of the archive icons, "7-Zip" in blue under it; at 16 and 32 px the zipper alone,
/// larger, since the name could not be read.
func drawAppIcon(_ pixels: CGFloat) {
    // Big Sur grid: an 824-unit squircle in the 1024 canvas, with the system's soft shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    rgb(0xE3E6EB).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0xFFFFFF), ending: rgb(0xE3E6EB))!.draw(in: squircle, angle: -90)
    rgb(0xD0D4DA).setStroke()
    squircle.lineWidth = pixels <= 32 ? 12 : 3
    squircle.stroke()

    if pixels <= 32 {
        drawSystemZipper(cx: 512, top: 860, scale: 1.05, color: rgb(0x8E9198), hole: rgb(0xF4F5F7), teeth: 4)
        return
    }
    drawSystemZipper(cx: 512, top: 850, scale: 0.8, color: rgb(0x9C9FA6), hole: rgb(0xF4F5F7), teeth: 4)
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 140, weight: .bold),
                                                     .foregroundColor: rgb(0x2A63E6)]
    let width = ("7-Zip" as NSString).size(withAttributes: attributes).width
    ("7-Zip" as NSString).draw(at: NSPoint(x: 512 - width / 2, y: 150), withAttributes: attributes)
}

// MARK: - document icons

struct DocIcon {
    let name: String
    let label: String
    let color: UInt32
}

// The label each format's icon carries (the colours are unused since the icons follow macOS's
// archive icon; kept for the contact sheet's grouping).
let docIcons: [DocIcon] = [
    DocIcon(name: "7z", label: "7Z", color: 0x2A63E6),
    DocIcon(name: "zip", label: "ZIP", color: 0xE69A00),
    DocIcon(name: "rar", label: "RAR", color: 0x8E44C9),
    DocIcon(name: "tar", label: "TAR", color: 0x2E9E5B),
    DocIcon(name: "gz", label: "GZ", color: 0x2E9E5B),
    DocIcon(name: "bz2", label: "BZ2", color: 0x2E9E5B),
    DocIcon(name: "xz", label: "XZ", color: 0x2E9E5B),
    DocIcon(name: "zst", label: "ZST", color: 0x2E9E5B),
    DocIcon(name: "lzma", label: "LZMA", color: 0x2E9E5B),
    DocIcon(name: "z", label: "Z", color: 0x2E9E5B),
    DocIcon(name: "iso", label: "ISO", color: 0x168C9E),
    DocIcon(name: "dmg", label: "DMG", color: 0x168C9E),
    DocIcon(name: "vhd", label: "VHD", color: 0x168C9E),
    DocIcon(name: "wim", label: "WIM", color: 0x168C9E),
    DocIcon(name: "hfs", label: "HFS", color: 0x168C9E),
    DocIcon(name: "apfs", label: "APFS", color: 0x168C9E),
    DocIcon(name: "ntfs", label: "NTFS", color: 0x168C9E),
    DocIcon(name: "fat", label: "FAT", color: 0x168C9E),
    DocIcon(name: "squashfs", label: "SQUASHFS", color: 0x168C9E),
    DocIcon(name: "cab", label: "CAB", color: 0xA0652D),
    DocIcon(name: "deb", label: "DEB", color: 0xA0652D),
    DocIcon(name: "rpm", label: "RPM", color: 0xA0652D),
    DocIcon(name: "cpio", label: "CPIO", color: 0xA0652D),
    DocIcon(name: "xar", label: "XAR", color: 0xA0652D),
    DocIcon(name: "lzh", label: "LZH", color: 0xA0652D),
    DocIcon(name: "arj", label: "ARJ", color: 0xA0652D),
    DocIcon(name: "split", label: "001", color: 0x59606B),
    DocIcon(name: "fm", label: "", color: 0x59606B),
]

/// macOS's archive document icon, drawn at the representation that suits `pixels`.
let systemArchiveIcon = NSWorkspace.shared.icon(for: .archive)

func drawDocIcon(_ doc: DocIcon, _ pixels: CGFloat) {
    let full = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    // `NSImage` picks the representation nearest the destination's pixel size.
    systemArchiveIcon.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: false, hints: [.ctm: NSAffineTransform(), .interpolation: NSImageInterpolation.high.rawValue])
    guard pixels >= 64, !doc.label.isEmpty else { return }
    drawSystemLabel(doc.label)
}

/// The extension as macOS writes it on its ZIP icon: SF Pro, caps 84 units high, centred, the
/// baseline 137 units above the bottom, light grey; a long label shrinks to stay on the sheet.
func drawSystemLabel(_ text: String) {
    let color = rgb(0xB6B6B6)
    let maxWidth: CGFloat = 440
    var size: CGFloat = 84 / NSFont.systemFont(ofSize: 100).capHeight * 100
    var attributes: [NSAttributedString.Key: Any] = [:]
    var width: CGFloat = 0
    while true {
        attributes = [.font: NSFont.systemFont(ofSize: size, weight: .regular), .foregroundColor: color]
        width = (text as NSString).size(withAttributes: attributes).width
        if width <= maxWidth || size < 40 { break }
        size *= 0.95
    }
    let font = attributes[.font] as! NSFont
    // draw(at:) takes the line's bottom: the baseline sits -descender above it.
    let origin = NSPoint(x: 512 - width / 2, y: 137 + font.descender)
    (text as NSString).draw(at: origin, withAttributes: attributes)
}

// MARK: - writing

func write(_ data: Data, _ path: String) throws {
    try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]

let assets = repo + "/Mac/Resources/Assets.xcassets"
let scratch = repo + "/Mac/build/macicons"
try? fm.removeItem(atPath: scratch)

// App icon
for (name, pixels) in sizes {
    try write(render(pixels, drawAppIcon), assets + "/AppIcon.appiconset/icon_\(name).png")
}
print("app icon: \(sizes.count) PNGs")

// Document icons
for doc in docIcons {
    let iconset = scratch + "/doc-\(doc.name).iconset"
    for (name, pixels) in sizes {
        try write(render(pixels) { drawDocIcon(doc, $0) }, iconset + "/icon_\(name).png")
    }
    let out = repo + "/Mac/Resources/Icons/doc-\(doc.name).icns"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset, "-o", out]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("iconutil failed for \(doc.name)") }
    let imageset = assets + "/doc-\(doc.name).imageset"
    if fm.fileExists(atPath: imageset) {
        try write(render(256) { drawDocIcon(doc, $0) }, imageset + "/doc-\(doc.name)_256.png")
        try write(render(512) { drawDocIcon(doc, $0) }, imageset + "/doc-\(doc.name)_512.png")
    }
}
print("document icons: \(docIcons.count) .icns")

// Contact sheet: the app icon, then every document icon, at 128 and 32 px.
let cell = 160, columns = 8
let rows = (docIcons.count + 1 + columns - 1) / columns
let sheetSize = NSSize(width: cell * columns, height: cell * rows)
let sheetRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width) * 2, pixelsHigh: Int(sheetSize.height) * 2,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
sheetRep.size = sheetSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheetRep)
rgb(0xF5F5F7).setFill()
NSRect(origin: .zero, size: sheetSize).fill()
let entries: [(String, (CGFloat) -> Void)] = [("App", drawAppIcon)] + docIcons.map { doc in (doc.name, { drawDocIcon(doc, $0) }) }
for (i, entry) in entries.enumerated() {
    let col = i % columns, row = i / columns
    let origin = NSPoint(x: col * cell, y: Int(sheetSize.height) - (row + 1) * cell)
    if let big = NSImage(data: render(256, entry.1)) {
        big.draw(in: NSRect(x: origin.x + 16, y: origin.y + 28, width: 112, height: 112))
    }
    if let small = NSImage(data: render(32, entry.1)) {
        small.draw(in: NSRect(x: origin.x + 128, y: origin.y + 28, width: 16, height: 16))
    }
    (entry.0 as NSString).draw(at: NSPoint(x: origin.x + 16, y: origin.y + 8),
                               withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray])
}
NSGraphicsContext.restoreGraphicsState()
try write(sheetRep.representation(using: .png, properties: [:])!, repo + "/Mac/build/screenshots/icons-mac-sheet.png")
print("contact sheet: Mac/build/screenshots/icons-mac-sheet.png")

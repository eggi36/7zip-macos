// make-mac-icons.swift -- the macOS-style app and document icons (native-look).
//
// Run by Mac/scripts/make-mac-icons.sh as
//
//     swift Mac/scripts/make-mac-icons.swift <repo>
//
// Draws everything with Core Graphics -- no SF Symbols (Apple's licence keeps them out of app
// icons) and no third-party art:
//
//   * the app icon: a macOS squircle with a blue gradient and the 7-Zip mark, a white archive box
//     closed by a zipper whose pull carries a geometric "7";
//   * one document icon per format family: the macOS document sheet with a folded corner, the
//     zipper mark in the family's colour and the extension as a label (no label at 16 and 32 px,
//     where it could not be read).
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

// MARK: - the mark: an archive box closed by a zipper

/// The zipper mark in `rect`: a rounded box in `body` with a zipper down its middle in `teeth`, the
/// slider near the top and its pull hanging down with a "7" cut out of it. `detail` drops the
/// teeth and the 7 at small sizes, where they would turn to mush.
func drawMark(in rect: NSRect, body: NSGradient, edge: NSColor, teeth: NSColor, pullFill: NSColor, detail: Bool) {
    let r = rect.width * 0.14
    let box = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    body.draw(in: box, angle: -90)
    edge.setStroke()
    box.lineWidth = max(2, rect.width * 0.012)
    box.stroke()

    // The lid seam: a band across the top quarter.
    let seamY = rect.maxY - rect.height * 0.24
    edge.withAlphaComponent(0.55).setFill()
    NSRect(x: rect.minX + rect.width * 0.02, y: seamY, width: rect.width * 0.96, height: max(2, rect.height * 0.012)).fill()

    // The zipper: two rows of teeth meeting at the middle, from the seam to near the bottom.
    let cx = rect.midX
    let toothW = rect.width * 0.075, toothH = rect.height * 0.034
    let top = seamY - rect.height * 0.02, bottom = rect.minY + rect.height * 0.08
    teeth.setFill()
    if detail {
        var y = top - toothH
        var left = true
        while y > bottom {
            let x = left ? cx - toothW + toothW * 0.18 : cx - toothW * 0.18
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: toothW, height: toothH),
                         xRadius: toothH * 0.35, yRadius: toothH * 0.35).fill()
            y -= toothH * 1.05
            left.toggle()
        }
    } else {
        NSRect(x: cx - toothW * 0.4, y: bottom, width: toothW * 0.8, height: top - bottom).fill()
    }

    // The slider at the seam and its pull, a rounded tab hanging down over the teeth.
    let sliderW = rect.width * 0.2, sliderH = rect.height * 0.1
    let slider = NSBezierPath(roundedRect: NSRect(x: cx - sliderW / 2, y: seamY - sliderH * 0.6, width: sliderW, height: sliderH),
                              xRadius: sliderH * 0.3, yRadius: sliderH * 0.3)
    teeth.setFill()
    slider.fill()
    let pullW = rect.width * 0.24, pullH = rect.height * 0.36
    let pullRect = NSRect(x: cx - pullW / 2, y: seamY - sliderH * 0.4 - pullH, width: pullW, height: pullH)
    let pull = NSBezierPath(roundedRect: pullRect, xRadius: pullW * 0.28, yRadius: pullW * 0.28)
    pullFill.setFill()
    pull.fill()
    teeth.setStroke()
    pull.lineWidth = max(2, rect.width * 0.014)
    pull.stroke()

    guard detail else { return }
    // A geometric "7" in the pull: a bar and a slanted stroke, in the teeth colour.
    let s = pullRect.insetBy(dx: pullW * 0.2, dy: pullH * 0.18)
    let bar = s.height * 0.16
    let seven = NSBezierPath()
    seven.move(to: NSPoint(x: s.minX, y: s.maxY))
    seven.line(to: NSPoint(x: s.maxX, y: s.maxY))
    seven.line(to: NSPoint(x: s.maxX, y: s.maxY - bar))
    seven.line(to: NSPoint(x: s.minX + s.width * 0.5, y: s.minY))
    seven.line(to: NSPoint(x: s.minX + s.width * 0.5 - bar * 1.15, y: s.minY))
    seven.line(to: NSPoint(x: s.maxX - bar * 1.1, y: s.maxY - bar))
    seven.line(to: NSPoint(x: s.minX, y: s.maxY - bar))
    seven.close()
    teeth.setFill()
    seven.fill()
}

// MARK: - app icon

func drawAppIcon(_ pixels: CGFloat) {
    // Big Sur grid: an 824-unit squircle in the 1024 canvas, with the system's soft shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    rgb(0x2A63E6).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0x5BA2FF), ending: rgb(0x1C45C9))!.draw(in: squircle, angle: -90)
    // a faint highlight across the top half
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(starting: NSColor(white: 1, alpha: 0.16), ending: NSColor(white: 1, alpha: 0))!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let mark = NSRect(x: 262, y: 222, width: 500, height: 560)
    NSGraphicsContext.saveGraphicsState()
    let markShadow = NSShadow()
    markShadow.shadowColor = NSColor(white: 0, alpha: 0.25)
    markShadow.shadowOffset = NSSize(width: 0, height: -8)
    markShadow.shadowBlurRadius = 18
    markShadow.set()
    rgb(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: mark, xRadius: 70, yRadius: 70).fill()
    NSGraphicsContext.restoreGraphicsState()
    drawMark(in: mark, body: NSGradient(starting: rgb(0xFFFFFF), ending: rgb(0xE6ECF5))!,
             edge: rgb(0xC5CFDD), teeth: rgb(0x23314D), pullFill: rgb(0xFFC63A), detail: pixels >= 64)
}

// MARK: - document icons

struct DocIcon {
    let name: String
    let label: String
    let color: UInt32
}

// Families: 7z blue, zip amber, rar purple, compressors green, disk images teal, packages brown,
// split / generic graphite.
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
    DocIcon(name: "squashfs", label: "SQFS", color: 0x168C9E),
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

func drawLabel(_ text: String, in box: NSRect, color: NSColor) {
    var size = box.height * 0.9
    var attributes: [NSAttributedString.Key: Any] = [:]
    var bounds = NSRect.zero
    while size > 8 {
        attributes = [.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: color,
                      .kern: -size * 0.01]
        bounds = (text as NSString).boundingRect(with: NSSize(width: 4000, height: 4000), options: [], attributes: attributes)
        if bounds.width <= box.width { break }
        size *= 0.94
    }
    let font = attributes[.font] as! NSFont
    let x = box.midX - bounds.width / 2
    // draw(at:) takes the line's bottom (the descender); the caps are centred in the box.
    let y = box.midY - font.capHeight / 2 + font.descender
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
}

func drawDocIcon(_ doc: DocIcon, _ pixels: CGFloat) {
    // The document sheet: 640 x 860 units, a 160-unit folded corner at the top right.
    let page = NSRect(x: 192, y: 82, width: 640, height: 860)
    let fold: CGFloat = 170
    let sheet = NSBezierPath()
    let r: CGFloat = 36
    sheet.move(to: NSPoint(x: page.minX + r, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX - r, y: page.minY))
    sheet.appendArc(from: NSPoint(x: page.maxX, y: page.minY), to: NSPoint(x: page.maxX, y: page.minY + r), radius: r)
    sheet.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    sheet.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    sheet.line(to: NSPoint(x: page.minX + r, y: page.maxY))
    sheet.appendArc(from: NSPoint(x: page.minX, y: page.maxY), to: NSPoint(x: page.minX, y: page.maxY - r), radius: r)
    sheet.line(to: NSPoint(x: page.minX, y: page.minY + r))
    sheet.appendArc(from: NSPoint(x: page.minX, y: page.minY), to: NSPoint(x: page.minX + r, y: page.minY), radius: r)
    sheet.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowBlurRadius = 16
    shadow.set()
    rgb(0xFFFFFF).setFill()
    sheet.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0xFFFFFF), ending: rgb(0xF1F3F7))!.draw(in: sheet, angle: -90)
    rgb(0xC9CED6).setStroke()
    sheet.lineWidth = pixels <= 32 ? 14 : 5
    sheet.stroke()
    // the folded corner
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold + 18, y: page.maxY - fold + 18))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    NSGradient(starting: rgb(0xE9EDF2), ending: rgb(0xCDD3DC))!.draw(in: corner, angle: -45)
    rgb(0xC9CED6).setStroke()
    corner.lineWidth = pixels <= 32 ? 10 : 4
    corner.stroke()

    // The mark in the family colour, and the label under it.
    let color = rgb(doc.color)
    let hasLabel = pixels >= 64 && !doc.label.isEmpty
    let markSize: CGFloat = hasLabel ? 330 : 400
    let markY: CGFloat = hasLabel ? 400 : 250
    let mark = NSRect(x: 512 - markSize / 2, y: markY, width: markSize, height: markSize * 1.08)
    let light = color.blended(withFraction: 0.18, of: .white) ?? color
    drawMark(in: mark, body: NSGradient(starting: light, ending: color)!, edge: color.blended(withFraction: 0.25, of: .black) ?? color,
             teeth: rgb(0xFFFFFF, 0.92), pullFill: color.blended(withFraction: 0.3, of: .black) ?? color, detail: pixels >= 64)
    if hasLabel {
        drawLabel(doc.label, in: NSRect(x: 252, y: 170, width: 520, height: 170), color: color)
    }
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

// make-mac-icons.swift -- the macOS-style app and document icons (native-look).
//
// Run by Mac/scripts/make-mac-icons.sh as
//
//     swift Mac/scripts/make-mac-icons.swift <repo>
//
// Draws everything with Core Graphics -- no SF Symbols (Apple's licence keeps them out of app
// icons) and no third-party art:
//
//   * the app icon: the archive icons' grey zipper, its pull in the 7-Zip blue -- no lettering, as
//     the HIG asks of app icons -- as an Icon Composer icon (Mac/Resources/AppIcon.icon): the
//     zipper is a layer of its own on a light gradient fill, and a dark fill in Dark mode; macOS
//     draws the tinted and clear looks itself, and Xcode makes the AppIcon.icns older systems use;
//   * one document icon per format: macOS's own archive icon (`UTType.archive`, the grey sheet with
//     the zipper that Finder shows for compressed files) with the extension under the zipper in
//     the grey, size and place of the label on macOS's ZIP icon (measured: caps 84 of 1024 units,
//     baseline 137 above the bottom, #B6B6B6). No label at 16 and 32 px, as on macOS's own icons.
//     The archive icon is taken from the Mac the script runs on, so the result follows that
//     macOS version; it is Apple's artwork -- fine for your own build, not for redistribution.
//
// Writes Mac/Resources/AppIcon.icon (icon.json and Assets/zipper.png), Mac/Resources/Icons/
// doc-<name>.icns (through `iconutil`) and the contact sheet Mac/build/screenshots/icons-mac-sheet.png
// (the app icon light and dark, then the document icons).

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
/// `hole` nil punches the pull's hole out (the app icon's layer shows its fill through it).
func drawSystemZipper(cx: CGFloat, top: CGFloat, scale k: CGFloat, color: NSColor, hole: NSColor?, teeth: Int,
                      pullColor: NSColor? = nil) {
    let pullW = 150 * k, pullH = 300 * k
    let pull = NSRect(x: cx - pullW / 2, y: top - pullH, width: pullW, height: pullH)
    let d = pullW * 0.42
    let holeRect = NSRect(x: cx - d / 2, y: pull.minY + pullW * 0.32, width: d, height: d)
    (pullColor ?? color).setFill()
    let pullPath = NSBezierPath(roundedRect: pull, xRadius: pullW / 2, yRadius: pullW / 2)
    if let hole {
        pullPath.fill()
        hole.setFill()
        NSBezierPath(ovalIn: holeRect).fill()
    } else {
        pullPath.append(NSBezierPath(ovalIn: holeRect))
        pullPath.windingRule = .evenOdd
        pullPath.fill()
    }
    color.setFill()
    let tw = 170 * k, th = 48 * k
    var y = pull.minY - 60 * k
    for i in 0..<teeth {
        let x = i % 2 == 0 ? cx - tw * 0.62 : cx - tw * 0.38
        NSBezierPath(roundedRect: NSRect(x: x, y: y - th, width: tw, height: th), xRadius: th / 2, yRadius: th / 2).fill()
        y -= th * 1.45
    }
}

/// The app icon's fills (Icon Composer derives a gradient from each): a light grey like Apple's
/// utilities, and a dark grey in Dark mode.
let appFillLight = (r: 0.93, g: 0.94, b: 0.95)
let appFillDark = (r: 0.22, g: 0.23, b: 0.25)

/// The app icon's one layer (the user's choice, variant A, without the "7-Zip" lettering the HIG
/// advises against): the grey zipper of the archive icons, centred on the full 1024 canvas (Icon
/// Composer masks it to the squircle), with its pull in the 7-Zip blue so it is not mistaken for
/// Archive Utility, and the pull's hole cut out.
func drawZipperLayer(_ pixels: CGFloat) {
    // The 824-unit tile of the old icon is the whole canvas now: scale 1.05 * 1024 / 824.
    drawSystemZipper(cx: 512, top: 915, scale: 1.305, color: rgb(0x9C9FA6), hole: nil, teeth: 4,
                     pullColor: rgb(0x2A63E6))
}

/// A preview of the app icon for the contact sheet: the layer on its fill inside the squircle.
func drawAppIconPreview(dark: Bool) -> (CGFloat) -> Void {
    { pixels in
        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
        let f = dark ? appFillDark : appFillLight
        let base = NSColor(srgbRed: f.r, green: f.g, blue: f.b, alpha: 1)
        NSGradient(starting: base.blended(withFraction: 0.35, of: dark ? .gray : .white) ?? base, ending: base)!
            .draw(in: squircle, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        let t = NSAffineTransform()
        t.translateX(by: 100, yBy: 100)
        t.scale(by: 824.0 / 1024)
        t.concat()
        drawZipperLayer(pixels)
        NSGraphicsContext.restoreGraphicsState()
    }
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

let scratch = repo + "/Mac/build/macicons"
try? fm.removeItem(atPath: scratch)

// App icon: an Icon Composer bundle, the zipper layer and the fills.
let iconBundle = repo + "/Mac/Resources/AppIcon.icon"
try write(render(1024, drawZipperLayer), iconBundle + "/Assets/zipper.png")
func srgb(_ c: (r: Double, g: Double, b: Double)) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,1.00000", c.r, c.g, c.b)
}
let iconJSON = """
{
  "fill" : {
    "automatic-gradient" : "\(srgb(appFillLight))"
  },
  "fill-specializations" : [
    {
      "appearance" : "dark",
      "value" : {
        "automatic-gradient" : "\(srgb(appFillDark))"
      }
    }
  ],
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "zipper.png",
          "name" : "zipper"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}

"""
try write(Data(iconJSON.utf8), iconBundle + "/icon.json")
print("app icon: Mac/Resources/AppIcon.icon (light and dark)")

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
}
print("document icons: \(docIcons.count) .icns")

// Contact sheet: the app icon, then every document icon, at 128 and 32 px.
let cell = 160, columns = 8
let rows = (docIcons.count + 2 + columns - 1) / columns
let sheetSize = NSSize(width: cell * columns, height: cell * rows)
let sheetRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width) * 2, pixelsHigh: Int(sheetSize.height) * 2,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
sheetRep.size = sheetSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheetRep)
rgb(0xF5F5F7).setFill()
NSRect(origin: .zero, size: sheetSize).fill()
let entries: [(String, (CGFloat) -> Void)] = [("App", drawAppIconPreview(dark: false)), ("App dark", drawAppIconPreview(dark: true))]
    + docIcons.map { doc in (doc.name, { drawDocIcon(doc, $0) }) }
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

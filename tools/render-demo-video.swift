// Renders Baddel's illustrated how-to video.
//
//   swift tools/render-demo-video.swift docs/media            writes the video, poster and captions
//   swift tools/render-demo-video.swift --frames docs/media/baddel-demo.mp4 /tmp/frames
//                                                            decodes frames from a video for checking
//
// The video is an illustration drawn by this script, not a screen recording.
// It uses a fixed sample ("hgsghl ugd;l" -> "السلام عليكم") and contains no
// captured screen content or personal data. Output: an H.264 MP4, a PNG
// poster, and WebVTT captions in English and Arabic.
import AppKit
import AVFoundation
import CoreText

let width = 1280, height = 720, fps: Int32 = 24
let duration = 23.0

// MARK: - Timeline (seconds)

let typed = Array("hgsghl ugd;l")
let tIntro = 0.0, tType = 2.0, tOnce = 6.0, tUndo = 10.0, tTwice = 13.5, tEnd = 19.0
let typeStart = tType + 0.6, typeStep = 0.2
let oncePress = tOnce + 1.0, onceFix = tOnce + 1.4, onceLayout = tOnce + 1.8
let undoClick = tUndo + 1.0, undoDone = tUndo + 1.3
let twicePress1 = tTwice + 1.1, twicePress2 = tTwice + 1.38, twiceFix = tTwice + 1.8, twiceLayout = tTwice + 2.2

/// The keyboard layout shown at a moment. Baddel switches the layout after
/// every verified correction, single press included, and Undo switches it back.
func layoutIsArabic(_ t: Double) -> Bool {
    if t >= twiceLayout { return true }
    return t >= onceLayout && t < undoDone
}
/// The most recent moment the layout changed, for the highlight ring.
func lastLayoutChange(_ t: Double) -> Double? {
    [twiceLayout, undoDone, onceLayout].first { t >= $0 }
}

struct Caption { let start: Double, end: Double, en: String, ar: String }
let captions: [Caption] = [
    Caption(start: tIntro, end: tType, en: "Baddel fixes text typed with the wrong keyboard layout. (Illustrated demo.)",
            ar: "«بدّل» يصحّح النص المكتوب بتخطيط لوحة مفاتيح خاطئ. (عرض توضيحي مصوّر.)"),
    Caption(start: tType, end: tOnce, en: "You meant to write Arabic, but the keyboard was on English: \"hgsghl ugd;l\".",
            ar: "أردتَ الكتابة بالعربية لكنّ لوحة المفاتيح كانت على الإنجليزية: «hgsghl ugd;l»."),
    Caption(start: tOnce, end: tUndo, en: "Press the shortcut once: Baddel fixes the last word, or the selected text, and switches the keyboard to Arabic.",
            ar: "اضغط الاختصار مرة واحدة: يصحّح «بدّل» آخر كلمة، أو النص المحدَّد، ويبدّل لوحة المفاتيح إلى العربية."),
    Caption(start: tUndo, end: tTwice, en: "Click Undo to restore the original text and the previous keyboard layout.",
            ar: "انقر «تراجع» لاستعادة النص الأصلي وتخطيط لوحة المفاتيح السابق."),
    Caption(start: tTwice, end: tEnd, en: "Press the shortcut twice quickly: Baddel fixes the whole field and switches the keyboard to Arabic.",
            ar: "اضغط الاختصار مرتين بسرعة: يصحّح «بدّل» الحقل كاملًا ويبدّل لوحة المفاتيح إلى العربية."),
    Caption(start: tEnd, end: duration, en: "Shortcut: Option-Shift-Space on macOS, Control-Alt-Space on Windows and Linux. Download: mahmoood.com/baddel",
            ar: "الاختصار: Option-Shift-Space على macOS، و Control-Alt-Space على Windows و Linux. التنزيل: mahmoood.com/baddel"),
]

// MARK: - Drawing helpers (top-left origin)

// The portfolio's own colours: site black, graphite, ivory and muted grey,
// with fine translucent borders and one soft violet accent. No green or teal.
let black = NSColor(srgbRed: 0x06 / 255, green: 0x07 / 255, blue: 0x0A / 255, alpha: 1)      // #06070A
let graphite = NSColor(srgbRed: 0x0E / 255, green: 0x10 / 255, blue: 0x16 / 255, alpha: 1)   // #0E1016
let raised = NSColor(srgbRed: 0x17 / 255, green: 0x1A / 255, blue: 0x23 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1)        // #F3F1EC
let soft = NSColor(srgbRed: 0xB4 / 255, green: 0xB6 / 255, blue: 0xBF / 255, alpha: 1)       // #B4B6BF
let accent = NSColor(srgbRed: 0xB7 / 255, green: 0xA8 / 255, blue: 0xF5 / 255, alpha: 1)     // soft violet
let hairline = NSColor.white.withAlphaComponent(0.14)

/// A restrained version of the portfolio's particle motif: a sparse diagonal
/// lattice of small dots, faint enough to stay behind the content.
func particles(in rect: NSRect, alpha: CGFloat) {
    let step: CGFloat = 34
    var row = 0
    var y = rect.minY + 10
    while y < rect.maxY {
        var x = rect.minX + (row % 2 == 0 ? 8 : 8 + step / 2)
        while x < rect.maxX {
            let fade = alpha * (0.35 + 0.65 * (x - rect.minX) / rect.width)
            NSColor.white.withAlphaComponent(fade).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2)).fill()
            x += step
        }
        y += step / 2
        row += 1
    }
}

func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
func ramp(_ t: Double, _ from: Double, _ length: Double) -> Double { ease((t - from) / length) }

func rounded(_ rect: NSRect, _ radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, line: CGFloat = 2) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = line; path.stroke() }
}

enum Align { case left, center, right }

@discardableResult
func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink,
          mono: Bool = false, align: Align = .left, rtl: Bool = false, alpha: CGFloat = 1) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
    let attributed = NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: color.withAlphaComponent(alpha), .paragraphStyle: style,
    ])
    let size = attributed.size()
    let originX: CGFloat
    switch align {
    case .left: originX = x
    case .center: originX = x - size.width / 2
    case .right: originX = x - size.width
    }
    attributed.draw(at: NSPoint(x: originX, y: y))
    return size.width
}

func keycap(_ label: String, centerX: CGFloat, y: CGFloat, glow: Double) {
    let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
    let w = (label as NSString).size(withAttributes: [.font: font]).width + 44
    let rect = NSRect(x: centerX - w / 2, y: y, width: w, height: 54)
    let fill = raised.blended(withFraction: CGFloat(glow) * 0.9, of: accent) ?? raised
    rounded(rect, 12, fill: fill, stroke: glow > 0.05 ? accent : hairline, line: 2)
    text(label, x: centerX, y: y + 11, size: 26, weight: .semibold,
         color: glow > 0.45 ? black : ink, align: .center)
}

/// The Baddel logo (docs/media/baddel-logo.png), shown on the first and last screens.
let logo: NSImage? = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/media/baddel-logo.png")
    return NSImage(contentsOf: url)
}()

/// Draws the logo, or, if the image is missing, a plain A ⇄ ب mark in its place.
func mark(centerX: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat) {
    if let logo {
        let side = size * 1.5
        logo.draw(in: NSRect(x: centerX - side / 2, y: y - size * 0.25, width: side, height: side), from: .zero,
                  operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        return
    }
    let gap = size * 0.34
    for (index, glyph) in ["A", "ب"].enumerated() {
        let x = centerX + (index == 0 ? -(size + gap / 2) : gap / 2)
        rounded(NSRect(x: x, y: y, width: size, height: size), size * 0.22,
                fill: raised.withAlphaComponent(alpha), stroke: hairline.withAlphaComponent(0.22 * alpha), line: 2)
        text(glyph, x: x + size / 2, y: y + size * (index == 0 ? 0.14 : 0.02), size: size * 0.56, weight: .bold,
             align: .center, rtl: index == 1, alpha: alpha)
    }
    text("⇄", x: centerX, y: y + size * 0.3, size: size * 0.3, weight: .medium, color: soft, align: .center, alpha: alpha)
}

// MARK: - One frame

func draw(_ t: Double) {
    black.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    particles(in: NSRect(x: 0, y: 0, width: width, height: height), alpha: 0.10)
    text("BADDEL", x: 56, y: 30, size: 24, weight: .bold, color: ink)
    text("بدّل", x: CGFloat(width) - 56, y: 22, size: 32, weight: .bold, color: ink, align: .right, rtl: true)
    // Always visible: this is an illustration, not a recording.
    let tag = "ILLUSTRATED DEMO  ·  عرض توضيحي مصوّر"
    let tagWidth = (tag as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold)]).width + 36
    rounded(NSRect(x: CGFloat(width) / 2 - tagWidth / 2, y: 26, width: tagWidth, height: 36), 18,
            fill: graphite, stroke: hairline, line: 1)
    text(tag, x: CGFloat(width) / 2, y: 33, size: 18, weight: .semibold, color: soft, align: .center)

    let card = NSRect(x: 56, y: 88, width: CGFloat(width) - 112, height: 560)
    rounded(card, 28, fill: graphite, stroke: hairline, line: 1)

    if t >= tEnd { drawEnd(t, card); return }
    if t < tType { drawIntro(t, card); return }

    // Step title, English then Arabic.
    let step: (Int, String, String, String?, String?)
    if t < tOnce { step = (1, "You type with the wrong keyboard layout", "تكتب وتخطيط لوحة المفاتيح خاطئ", nil, nil) }
    else if t < tUndo { step = (2, "Press once: fixes the last word", "ضغطة واحدة: تصحيح آخر كلمة", "or the selected text; the keyboard switches too", "أو النص المحدَّد، ويتبدّل التخطيط أيضًا") }
    else if t < tTwice { step = (3, "Undo restores the text and the layout", "«تراجع» يستعيد النص والتخطيط", nil, nil) }
    else { step = (4, "Press twice quickly: fixes the whole field", "ضغطتان سريعتان: تصحيح الحقل كاملًا", "and the keyboard switches to Arabic", "وتتحوّل لوحة المفاتيح إلى العربية") }

    rounded(NSRect(x: card.minX + 44, y: card.minY + 36, width: 92, height: 38), 19, fill: raised, stroke: hairline, line: 1)
    text("STEP \(step.0)", x: card.minX + 90, y: card.minY + 44, size: 17, weight: .bold, color: soft, align: .center)
    text(step.1, x: card.minX + 44, y: card.minY + 92, size: 46, weight: .bold)
    text(step.2, x: card.maxX - 44, y: card.minY + 150, size: 44, weight: .bold, align: .right, rtl: true)
    if let en = step.3, let ar = step.4 {
        text(en, x: card.minX + 44, y: card.minY + 216, size: 26, color: soft)
        text(ar, x: card.maxX - 44, y: card.minY + 212, size: 28, color: soft, align: .right, rtl: true)
    }

    // What the field holds at this moment.
    var content = String(typed), isArabic = false
    if t < tOnce {
        let shown = max(0, min(typed.count, Int((t - typeStart) / typeStep) + 1))
        content = t < typeStart ? "" : String(typed.prefix(shown))
    } else if t < tUndo {
        if t >= onceFix { content = "hgsghl عليكم" }
    } else if t < tTwice {
        content = t >= undoDone ? "hgsghl ugd;l" : "hgsghl عليكم"
    } else if t >= twiceFix {
        content = "السلام عليكم"; isArabic = true
    }
    let arabicLayout = layoutIsArabic(t)

    let field = NSRect(x: card.minX + 44, y: card.minY + 270, width: card.width - 88 - 150, height: 108)
    rounded(field, 16, fill: black, stroke: hairline, line: 2)
    let flash = max(1 - abs(t - onceFix - 0.15) / 0.3, 1 - abs(t - twiceFix - 0.15) / 0.3, 1 - abs(t - undoDone - 0.15) / 0.3)
    if flash > 0 { rounded(field.insetBy(dx: -4, dy: -4), 20, fill: .clear, stroke: accent.withAlphaComponent(CGFloat(flash)), line: 4) }
    var textWidth: CGFloat = 0
    if isArabic {
        textWidth = text(content, x: field.maxX - 30, y: field.minY + 14, size: 62, weight: .semibold, align: .right, rtl: true)
    } else {
        textWidth = text(content, x: field.minX + 30, y: field.minY + 20, size: 56, weight: .medium, mono: true)
    }
    if Int(t * 2) % 2 == 0 {   // caret
        let caretX = isArabic ? field.maxX - 30 - textWidth - 8 : field.minX + 30 + textWidth + 6
        ink.setFill(); NSRect(x: caretX, y: field.minY + 22, width: 4, height: 64).fill()
    }

    // Active keyboard layout.
    let chipRect = NSRect(x: field.maxX + 22, y: field.minY + 16, width: 128, height: 76)
    rounded(chipRect, 16, fill: raised, stroke: arabicLayout ? accent : hairline, line: arabicLayout ? 3 : 2)
    text(arabicLayout ? "ع" : "EN", x: chipRect.midX, y: chipRect.minY + (arabicLayout ? 6 : 16), size: arabicLayout ? 44 : 34,
         weight: .bold, color: arabicLayout ? accent : ink, align: .center, rtl: arabicLayout)
    if let changed = lastLayoutChange(t) {
        let ring = 1 - ramp(t, changed, 0.45)
        if ring > 0 { rounded(chipRect.insetBy(dx: -5, dy: -5), 20, fill: .clear, stroke: accent.withAlphaComponent(CGFloat(ring) * 0.9), line: 5) }
    }
    text("keyboard · لوحة المفاتيح", x: chipRect.midX, y: chipRect.maxY + 8, size: 14, color: soft, align: .center)

    // Undo button, offered after a correction.
    let undoVisible = (t >= onceFix + 0.25 && t < undoDone) || t >= twiceFix + 0.25
    if undoVisible {
        let button = NSRect(x: field.minX, y: field.maxY + 16, width: 250, height: 50)
        let clicking = max(0, 1 - abs(t - undoClick) / 0.22)
        rounded(button, 12, fill: raised, stroke: hairline, line: 1)
        text("Fixed", x: button.minX + 18, y: button.minY + 12, size: 21, weight: .medium, color: soft)
        let inner = NSRect(x: button.minX + 92, y: button.minY + 8, width: 146, height: 34)
        rounded(inner, 8, fill: clicking > 0.1 ? accent : ink)
        text("Undo · تراجع", x: inner.midX, y: inner.minY + 5, size: 18, weight: .semibold, color: black, align: .center)
        if clicking > 0 { rounded(inner.insetBy(dx: -6, dy: -6), 12, fill: .clear, stroke: accent.withAlphaComponent(CGFloat(clicking)), line: 5) }
    }

    // The shortcut, with a pulse for each press.
    func pulse(_ at: Double) -> Double { max(0, 1 - abs(t - at) / 0.16) }
    let glow = max(pulse(oncePress), pulse(twicePress1), pulse(twicePress2))
    let keysY = card.maxY - 92
    keycap("⌥ ⇧ Space", centerX: card.minX + 44 + 110, y: keysY, glow: t >= tOnce ? glow : 0)
    text("macOS", x: card.minX + 44 + 232, y: keysY + 14, size: 20, color: soft)
    keycap("Ctrl + Alt + Space", centerX: card.minX + 500, y: keysY, glow: t >= tOnce ? glow : 0)
    text("Windows · Linux", x: card.minX + 660, y: keysY + 14, size: 20, color: soft)
    var presses = 0
    if (t >= oncePress && t < tUndo) { presses = 1 }
    if t >= twicePress1 && t >= tTwice { presses = t >= twicePress2 ? 2 : 1 }
    if presses > 0 {
        rounded(NSRect(x: card.maxX - 44 - 150, y: keysY, width: 150, height: 54), 27, fill: raised, stroke: accent, line: 2)
        text(presses == 1 ? "× 1 press" : "× 2 presses", x: card.maxX - 44 - 75, y: keysY + 13, size: 22, weight: .bold, color: accent, align: .center)
    }

    footer()
}

func footer() {
    text("mahmoood.com/baddel", x: 56, y: CGFloat(height) - 50, size: 20, weight: .medium, color: ink)
    text("Free and open source · MIT", x: CGFloat(width) - 56, y: CGFloat(height) - 50, size: 20, color: soft, align: .right)
}

func drawIntro(_ t: Double, _ card: NSRect) {
    let a = CGFloat(ramp(t, 0.1, 0.5))
    mark(centerX: card.midX, y: card.minY + 64, size: 120, alpha: a)
    text("Fix text typed with the wrong keyboard layout", x: card.midX, y: card.minY + 244, size: 44, weight: .bold, align: .center, alpha: a)
    text("صحِّح النص المكتوب بتخطيط لوحة مفاتيح خاطئ", x: card.midX, y: card.minY + 312, size: 44, weight: .bold, align: .center, rtl: true, alpha: a)
    text("Arabic  ⇄  English · العربية  ⇄  الإنجليزية", x: card.midX, y: card.minY + 400, size: 28, color: soft, align: .center, alpha: a)
    footer()
}

func drawEnd(_ t: Double, _ card: NSRect) {
    let a = CGFloat(ramp(t, tEnd, 0.4))
    mark(centerX: card.midX, y: card.minY + 42, size: 92, alpha: a)
    text("Baddel  ·  بدّل", x: card.midX, y: card.minY + 168, size: 48, weight: .bold, align: .center, alpha: a)
    let rows: [(String, String)] = [("Once", "Selection, or the last word  ·  التحديد أو آخر كلمة"),
                                    ("Twice", "The whole field  ·  الحقل كاملًا"),
                                    ("Undo", "Restores text and layout  ·  يستعيد النص والتخطيط"),
                                    ("Layout", "Follows each correction  ·  يتبع كل تصحيح")]
    for (index, row) in rows.enumerated() {
        let y = card.minY + 228 + CGFloat(index) * 50
        rounded(NSRect(x: card.minX + 150, y: y, width: 130, height: 44), 22, fill: raised, stroke: hairline, line: 1)
        text(row.0, x: card.minX + 215, y: y + 9, size: 21, weight: .bold, color: soft, align: .center, alpha: a)
        text(row.1, x: card.minX + 306, y: y + 6, size: 25, alpha: a)
    }
    keycap("⌥ ⇧ Space", centerX: card.midX - 250, y: card.maxY - 104, glow: 0)
    text("macOS", x: card.midX - 250, y: card.maxY - 44, size: 18, color: soft, align: .center)
    keycap("Ctrl + Alt + Space", centerX: card.midX + 150, y: card.maxY - 104, glow: 0)
    text("Windows  ·  Linux (X11)", x: card.midX + 150, y: card.maxY - 44, size: 18, color: soft, align: .center)
    footer()
}

// MARK: - Rendering

func render(_ t: Double, into buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(t)
    NSGraphicsContext.restoreGraphicsState()
}

func makeBuffer() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
    return buffer!
}

func writePNG(_ t: Double, to url: URL) throws {
    let buffer = makeBuffer(); render(t, into: buffer)
    let image = CIImage(cvPixelBuffer: buffer)
    let rep = NSBitmapImageRep(ciImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func vtt(_ language: KeyPath<Caption, String>) -> String {
    func stamp(_ s: Double) -> String { String(format: "%02d:%02d.%03d", Int(s) / 60, Int(s) % 60, Int((s - floor(s)) * 1000)) }
    return "WEBVTT\n\n" + captions.enumerated().map { "\($0 + 1)\n\(stamp($1.start)) --> \(stamp($1.end))\n\($1[keyPath: language])\n" }.joined(separator: "\n")
}

let arguments = CommandLine.arguments
if arguments.count >= 4, arguments[1] == "--frames" {
    // Decode real frames from a finished file, to check what viewers will see.
    let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[2]))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
    try FileManager.default.createDirectory(atPath: arguments[3], withIntermediateDirectories: true)
    let track = asset.tracks(withMediaType: .video).first!
    print("duration=\(String(format: "%.2f", asset.duration.seconds))s size=\(Int(track.naturalSize.width))x\(Int(track.naturalSize.height)) fps=\(track.nominalFrameRate) audioTracks=\(asset.tracks(withMediaType: .audio).count)")
    for time in [1.0, 4.5, 7.0, 8.5, 11.0, 12.5, 14.9, 15.4, 17.5, 21.0] {
        let image = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(arguments[3])/frame-\(String(format: "%04.1f", time)).png"))
    }
    print("frames written to \(arguments[3])")
    exit(0)
}

let out = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "docs/media")
let video = out.appendingPathComponent("baddel-demo.mp4")
try? FileManager.default.removeItem(at: video)
let writer = try AVAssetWriter(outputURL: video, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true   // metadata first, so playback can start while loading
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 420_000, AVVideoMaxKeyFrameIntervalKey: 48,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
writer.add(input)
writer.startWriting(); writer.startSession(atSourceTime: .zero)
let total = Int(duration * Double(fps))
for frame in 0..<total {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    let buffer = makeBuffer()
    render(Double(frame) / Double(fps), into: buffer)
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.endSession(atSourceTime: CMTime(value: CMTimeValue(total), timescale: fps))
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { print("failed: \(String(describing: writer.error))"); exit(1) }

try writePNG(tTwice + 3.2, to: out.appendingPathComponent("baddel-demo-poster.png"))
try vtt(\.en).write(to: out.appendingPathComponent("baddel-demo.en.vtt"), atomically: true, encoding: .utf8)
try vtt(\.ar).write(to: out.appendingPathComponent("baddel-demo.ar.vtt"), atomically: true, encoding: .utf8)
let bytes = (try FileManager.default.attributesOfItem(atPath: video.path)[.size] as? Int) ?? 0
print("wrote \(video.lastPathComponent): \(total) frames, \(bytes / 1024) KB; poster and captions alongside")

#!/usr/bin/env swift

import AppKit

struct Panel {
    let source: String
    let output: String
    let number: String
    let headline: String
    let subline: String
}

struct DeviceClass {
    let key: String
    let outputDirectory: String
    let outputSize: NSSize
    let screenshotWidthRatio: CGFloat
    let screenshotTopRatio: CGFloat
    let cornerRatio: CGFloat
}

let panels = [
    Panel(
        source: "01-home.png",
        output: "01-one-word-a-day.png",
        number: "01",
        headline: "1日1つ、\n自分の言葉を残す。",
        subline: "今日のお題から、すぐ書ける。"
    ),
    Panel(
        source: "02-compose.png",
        output: "02-write-as-you-are.png",
        number: "02",
        headline: "今日のことを、\nそのまま書く。",
        subline: "未来の自分にも、そっと届ける。"
    ),
    Panel(
        source: "03-profile.png",
        output: "03-meet-your-past-self.png",
        number: "03",
        headline: "ときどき、\n過去の自分に会う。",
        subline: "週刊の振り返りと、1か月前の言葉。"
    ),
]

let deviceClasses = [
    DeviceClass(
        key: "iphone",
        outputDirectory: "iPhone",
        outputSize: NSSize(width: 1284, height: 2778),
        screenshotWidthRatio: 0.80,
        screenshotTopRatio: 0.70,
        cornerRatio: 0.075
    ),
    DeviceClass(
        key: "ipad",
        outputDirectory: "iPad",
        outputSize: NSSize(width: 2048, height: 2732),
        screenshotWidthRatio: 0.84,
        screenshotTopRatio: 0.69,
        cornerRatio: 0.028
    ),
]

let background = NSColor(srgbRed: 251 / 255, green: 250 / 255, blue: 247 / 255, alpha: 1)
let ink = NSColor(srgbRed: 32 / 255, green: 28 / 255, blue: 22 / 255, alpha: 1)
let secondaryInk = NSColor(srgbRed: 104 / 255, green: 95 / 255, blue: 81 / 255, alpha: 1)
let accent = NSColor(srgbRed: 14 / 255, green: 109 / 255, blue: 98 / 255, alpha: 1)
let border = NSColor(srgbRed: 222 / 255, green: 220 / 255, blue: 213 / 255, alpha: 1)

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectRoot = scriptURL.deletingLastPathComponent()
let assetRoot = projectRoot
    .appendingPathComponent("AppStoreAssets")
    .appendingPathComponent("Screenshots")
    .appendingPathComponent("Simple")

func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont(name: weight == .bold ? "HiraginoSans-W7" : "HiraginoSans-W4", size: size)
        ?? NSFont.systemFont(ofSize: size, weight: weight)
}

func paragraph(alignment: NSTextAlignment, lineSpacing: CGFloat = 0) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineSpacing = lineSpacing
    style.lineBreakMode = .byWordWrapping
    return style
}

func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    lineSpacing: CGFloat = 0
) {
    text.draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph(alignment: alignment, lineSpacing: lineSpacing),
        ]
    )
}

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func render(panel: Panel, device: DeviceClass) -> Bool {
    let rawURL = assetRoot
        .appendingPathComponent("raw")
        .appendingPathComponent(device.key)
        .appendingPathComponent(panel.source)
    let outputDirectory = assetRoot.appendingPathComponent(device.outputDirectory)
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    guard let screenshot = NSImage(contentsOf: rawURL),
          let representation = NSBitmapImageRep(data: screenshot.tiffRepresentation ?? Data()) else {
        print("  ✗ 読み込み失敗: \(rawURL.path)")
        return false
    }

    let width = device.outputSize.width
    let height = device.outputSize.height
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return false
    }
    bitmap.size = device.outputSize

    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        return false
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    background.setFill()
    canvas.fill()

    let horizontalInset = width * 0.10
    let brandY = height * 0.925
    let numberSize = width * 0.026
    drawText(
        "HitoLog",
        in: NSRect(x: horizontalInset, y: brandY, width: width * 0.3, height: width * 0.06),
        font: font(size: numberSize, weight: .bold),
        color: accent
    )
    drawText(
        panel.number,
        in: NSRect(x: width - horizontalInset - width * 0.12, y: brandY, width: width * 0.12, height: width * 0.06),
        font: font(size: numberSize, weight: .regular),
        color: secondaryInk,
        alignment: .right
    )

    let ruleY = height * 0.902
    let rule = NSRect(x: horizontalInset, y: ruleY, width: width * 0.07, height: max(width * 0.006, 4))
    accent.setFill()
    NSBezierPath(roundedRect: rule, xRadius: rule.height / 2, yRadius: rule.height / 2).fill()

    drawText(
        panel.headline,
        in: NSRect(
            x: horizontalInset,
            y: height * 0.765,
            width: width * 0.82,
            height: height * 0.13
        ),
        font: font(size: width * 0.068, weight: .bold),
        color: ink,
        lineSpacing: width * 0.012
    )
    drawText(
        panel.subline,
        in: NSRect(
            x: horizontalInset,
            y: height * 0.725,
            width: width * 0.82,
            height: height * 0.045
        ),
        font: font(size: width * 0.029, weight: .regular),
        color: secondaryInk
    )

    let screenshotWidth = width * device.screenshotWidthRatio
    let sourceRatio = CGFloat(representation.pixelsHigh) / CGFloat(representation.pixelsWide)
    let screenshotHeight = screenshotWidth * sourceRatio
    let screenshotTop = height * device.screenshotTopRatio
    let screenshotRect = NSRect(
        x: (width - screenshotWidth) / 2,
        y: screenshotTop - screenshotHeight,
        width: screenshotWidth,
        height: screenshotHeight
    )
    let cornerRadius = screenshotWidth * device.cornerRatio
    let screenshotPath = roundedPath(screenshotRect, radius: cornerRadius)

    let context = graphics.cgContext
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -width * 0.012),
        blur: width * 0.035,
        color: NSColor.black.withAlphaComponent(0.12).cgColor
    )
    NSColor.white.setFill()
    screenshotPath.fill()
    context.restoreGState()

    context.saveGState()
    screenshotPath.addClip()
    screenshot.draw(in: screenshotRect, from: .zero, operation: .sourceOver, fraction: 1)
    context.restoreGState()

    border.setStroke()
    screenshotPath.lineWidth = max(width * 0.0015, 1)
    screenshotPath.stroke()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        return false
    }
    let outputURL = outputDirectory.appendingPathComponent(panel.output)
    do {
        try png.write(to: outputURL)
        print("  ✓ \(device.outputDirectory)/\(panel.output)")
        return true
    } catch {
        print("  ✗ 書き込み失敗: \(error)")
        return false
    }
}

print("▶ シンプルなApp Storeパネルを生成...")
var successCount = 0
var totalCount = 0
for device in deviceClasses {
    for panel in panels {
        totalCount += 1
        if render(panel: panel, device: device) {
            successCount += 1
        }
    }
}
print("✅ \(successCount)/\(totalCount) 枚: \(assetRoot.path)")
if successCount != totalCount {
    exit(1)
}

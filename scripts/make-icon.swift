// 绘制 App 图标并生成 AppIcon.appiconset。
// 用法：swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let accent = NSColor(srgbRed: 0.47, green: 0.58, blue: 1.0, alpha: 1)

/// 连续曲率圆角矩形（超椭圆），接近 macOS 图标外形
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = center.x + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = center.y + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    // 投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // 背景
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1).cgColor,
        NSColor(srgbRed: 0.035, green: 0.037, blue: 0.045, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // 发光
    let glow = CGGradient(colorsSpace: space, colors: [accent.withAlphaComponent(0.45).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 600), startRadius: 0, endCenter: CGPoint(x: 560, y: 600), endRadius: 420, options: [])

    // 遥控器：倾斜的铝质机身
    ctx.saveGState()
    ctx.translateBy(x: 560, y: 560)
    ctx.rotate(by: -0.30)
    let remoteW: CGFloat = 340
    let remote = CGRect(x: -remoteW / 2, y: -880, width: remoteW, height: 1100)
    let remotePath = CGPath(roundedRect: remote, cornerWidth: remoteW * 0.3, cornerHeight: remoteW * 0.3, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 60, color: NSColor.black.withAlphaComponent(0.7).cgColor)
    ctx.addPath(remotePath)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(remotePath)
    ctx.clip()
    let metal = CGGradient(colorsSpace: space, colors: [
        NSColor(white: 0.62, alpha: 1).cgColor, NSColor(white: 0.86, alpha: 1).cgColor,
        NSColor(white: 0.95, alpha: 1).cgColor, NSColor(white: 0.80, alpha: 1).cgColor, NSColor(white: 0.58, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.18, 0.48, 0.85, 1])!
    ctx.drawLinearGradient(metal, start: CGPoint(x: remote.minX, y: 0), end: CGPoint(x: remote.maxX, y: 0), options: [])
    ctx.restoreGState()
    ctx.addPath(remotePath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()

    // 触控板
    let padCenter = CGPoint(x: 0, y: 220 - remoteW * 0.70)
    let padR = remoteW * 0.42
    let innerR = remoteW * 0.20
    let pad = CGGradient(colorsSpace: space, colors: [NSColor(white: 0.17, alpha: 1).cgColor, NSColor(white: 0.04, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: padCenter.x - padR, y: padCenter.y - padR, width: padR * 2, height: padR * 2))
    ctx.clip()
    ctx.drawRadialGradient(pad, startCenter: CGPoint(x: padCenter.x, y: padCenter.y + 20), startRadius: 0, endCenter: padCenter, endRadius: padR, options: [])
    ctx.restoreGState()

    // 发光扇区（上）
    let segment = CGMutablePath()
    segment.addArc(center: padCenter, radius: padR - 4, startAngle: .pi / 2 + 0.72, endAngle: .pi / 2 - 0.72, clockwise: true)
    segment.addArc(center: padCenter, radius: innerR + 8, startAngle: .pi / 2 - 0.72, endAngle: .pi / 2 + 0.72, clockwise: false)
    segment.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 50, color: accent.cgColor)
    ctx.addPath(segment)
    ctx.setFillColor(accent.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addEllipse(in: CGRect(x: padCenter.x - innerR, y: padCenter.y - innerR, width: innerR * 2, height: innerR * 2))
    ctx.setFillColor(NSColor(white: 0.10, alpha: 1).cgColor)
    ctx.fillPath()

    // 两颗按键
    for (dx, dy) in [(-0.215, -0.73), (0.215, -0.73)] {
        let c = CGPoint(x: dx * remoteW, y: padCenter.y + dy * remoteW)
        let r = remoteW * 0.15
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setFillColor(NSColor(white: 0.09, alpha: 1).cgColor)
        ctx.fillPath()
    }
    ctx.restoreGState()

    // 顶部高光与描边
    let sheen = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.setLineWidth(2)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(points * scale)
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: pixels).representation(using: .png, properties: [:])!.write(to: outputDir.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outputDir.appending(path: "Contents.json"))
print("已生成 \(images.count) 个图标到 \(outputDir.path)")

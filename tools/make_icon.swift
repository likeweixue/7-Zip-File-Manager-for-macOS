import AppKit
import Foundation

// 生成 7-Zip File Manager 的 AppIcon.icns
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./build/icon"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let S: CGFloat = 1024

func drawIcon() -> NSBitmapImageRep {
    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()

    // 圆角方形底
    let base = NSRect(x: 26, y: 26, width: S - 52, height: S - 52)
    let bg = NSBezierPath(roundedRect: base, xRadius: 210, yRadius: 210)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.61, blue: 0.85, alpha: 1),
        NSColor(srgbRed: 0.11, green: 0.35, blue: 0.58, alpha: 1)
    ])!
    gradient.draw(in: bg, angle: -90)

    // 内部白色卡片（代表压缩包）
    let cardRect = NSRect(x: 152, y: 196, width: 720, height: 632)
    let card = NSBezierPath(roundedRect: cardRect, xRadius: 46, yRadius: 46)
    NSColor(srgbRed: 0.99, green: 0.99, blue: 0.99, alpha: 1).setFill()
    card.fill()

    // 卡片顶部的黄色条（档案/文件夹暗示）
    let bandRect = NSRect(x: 152, y: 726, width: 720, height: 102)
    let band = NSBezierPath(roundedRect: bandRect, xRadius: 46, yRadius: 46)
    NSColor(srgbRed: 0.95, green: 0.72, blue: 0.18, alpha: 1).setFill()
    band.fill()
    NSColor(srgbRed: 0.95, green: 0.72, blue: 0.18, alpha: 1).setFill()
    NSRect(x: 152, y: 726, width: 720, height: 52).fill()

    // 7z 文字
    let text = "7z" as NSString
    let font = NSFont.systemFont(ofSize: 360, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.10, green: 0.28, blue: 0.47, alpha: 1)
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (S - size.width) / 2, y: 330), withAttributes: attrs)

    image.unlockFocus()

    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep
}

let rep = drawIcon()
let masterURL = URL(fileURLWithPath: outDir).appendingPathComponent("icon_1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: masterURL)

let iconset = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(px)", "\(px)", masterURL.path, "--out",
                      iconset.appendingPathComponent(name).path]
    try? task.run()
    task.waitUntilExit()
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o",
                      URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.icns").path]
try? iconutil.run()
iconutil.waitUntilExit()
print("icon done")

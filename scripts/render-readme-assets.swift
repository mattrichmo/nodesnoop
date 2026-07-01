import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: "docs/assets/nodesnoop-product.png")
let size = NSSize(width: 1800, height: 1125)

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xff) / 255.0
        let green = CGFloat((hex >> 8) & 0xff) / 255.0
        let blue = CGFloat(hex & 0xff) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()

    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func line(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(hex: 0xf4f4ef), align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    (text as NSString).draw(
        in: NSRect(x: x, y: y, width: width, height: size * 1.35),
        withAttributes: attributes
    )
}

func drawMonoText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(hex: 0xf4f4ef)) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    (text as NSString).draw(
        in: NSRect(x: x, y: y, width: width, height: size * 1.35),
        withAttributes: attributes
    )
}

func drawSpruce(at origin: NSPoint, size: CGFloat, color: NSColor) {
    let scale = size / 18.0
    let transform = AffineTransform(translationByX: origin.x, byY: origin.y)
    let scaleTransform = AffineTransform(scaleByX: scale, byY: scale)

    let path = NSBezierPath()
    path.move(to: NSPoint(x: 9.0, y: 0.8))
    path.line(to: NSPoint(x: 4.3, y: 6.0))
    path.line(to: NSPoint(x: 6.5, y: 6.0))
    path.line(to: NSPoint(x: 3.7, y: 9.6))
    path.line(to: NSPoint(x: 6.4, y: 9.6))
    path.line(to: NSPoint(x: 4.7, y: 12.1))
    path.line(to: NSPoint(x: 8.0, y: 12.1))
    path.line(to: NSPoint(x: 8.0, y: 15.0))
    path.line(to: NSPoint(x: 10.0, y: 15.0))
    path.line(to: NSPoint(x: 10.0, y: 12.1))
    path.line(to: NSPoint(x: 13.3, y: 12.1))
    path.line(to: NSPoint(x: 11.6, y: 9.6))
    path.line(to: NSPoint(x: 14.3, y: 9.6))
    path.line(to: NSPoint(x: 11.5, y: 6.0))
    path.line(to: NSPoint(x: 13.7, y: 6.0))
    path.close()
    path.transform(using: scaleTransform)
    path.transform(using: transform)
    color.setFill()
    path.fill()
}

func drawChevron(x: CGFloat, y: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: y))
    path.line(to: NSPoint(x: x + 10, y: y + 10))
    path.line(to: NSPoint(x: x, y: y + 20))
    color.setStroke()
    path.lineWidth = 4
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func drawMenuRow(x: CGFloat, y: CGFloat, width: CGFloat, title: String, detail: String, selected: Bool = false) {
    if selected {
        roundedRect(NSRect(x: x - 12, y: y - 8, width: width + 24, height: 48), radius: 8, fill: NSColor(hex: 0x3182de))
    }

    let color = selected ? NSColor.white : NSColor(hex: 0xf2f2ed)
    drawText(title, x: x, y: y, width: width * 0.48, size: 24, weight: .semibold, color: color)
    drawText(detail, x: x + width * 0.50, y: y + 2, width: width * 0.39, size: 21, weight: .medium, color: color)
    drawChevron(x: x + width - 8, y: y + 6, color: color)
}

func drawSubmenuRow(x: CGFloat, y: CGFloat, width: CGFloat, text: String, emphasis: Bool = false) {
    drawText(text, x: x, y: y, width: width, size: 23, weight: emphasis ? .semibold : .medium, color: NSColor(hex: 0xf6f6f0))
}

let image = NSImage(size: size, flipped: true) { rect in
    guard let context = NSGraphicsContext.current?.cgContext else {
        return false
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    NSGradient(colors: [
        NSColor(hex: 0x08261f),
        NSColor(hex: 0x173d34),
        NSColor(hex: 0x6f7d45)
    ])?.draw(in: rect, angle: -35)

    roundedRect(NSRect(x: 0, y: 0, width: size.width, height: 56), radius: 0, fill: NSColor(hex: 0x07100e, alpha: 0.96))
    drawSpruce(at: NSPoint(x: 28, y: 17), size: 22, color: NSColor(hex: 0xe7eee4))
    drawText("NodeSnoop", x: 64, y: 15, width: 180, size: 18, weight: .semibold, color: NSColor(hex: 0xf4f3ed))
    drawText("Wed 9:41", x: size.width - 152, y: 16, width: 100, size: 16, weight: .medium, color: NSColor(hex: 0xf4f3ed), align: .right)

    let browser = NSRect(x: 120, y: 108, width: 1560, height: 884)
    roundedRect(browser, radius: 16, fill: NSColor(hex: 0xf5f7f2), stroke: NSColor(hex: 0x0e261f, alpha: 0.38), lineWidth: 1)
    roundedRect(NSRect(x: browser.minX, y: browser.minY, width: browser.width, height: 76), radius: 16, fill: NSColor(hex: 0x0b332b))
    roundedRect(NSRect(x: browser.minX, y: browser.minY + 56, width: browser.width, height: 20), radius: 0, fill: NSColor(hex: 0x0b332b))
    roundedRect(NSRect(x: browser.minX + 34, y: browser.minY + 22, width: 14, height: 14), radius: 7, fill: NSColor(hex: 0xff6257))
    roundedRect(NSRect(x: browser.minX + 58, y: browser.minY + 22, width: 14, height: 14), radius: 7, fill: NSColor(hex: 0xffbd2e))
    roundedRect(NSRect(x: browser.minX + 82, y: browser.minY + 22, width: 14, height: 14), radius: 7, fill: NSColor(hex: 0x2fd45a))
    roundedRect(NSRect(x: browser.minX + 130, y: browser.minY + 18, width: 440, height: 30), radius: 12, fill: NSColor(hex: 0x1f5146))
    drawText("localhost:3000", x: browser.minX + 152, y: browser.minY + 22, width: 220, size: 15, weight: .medium, color: NSColor(hex: 0xdde9df))

    let menu = NSRect(x: 742, y: 92, width: 820, height: 640)
    context.setShadow(offset: CGSize(width: 0, height: 24), blur: 34, color: NSColor.black.withAlphaComponent(0.36).cgColor)
    roundedRect(menu, radius: 14, fill: NSColor(hex: 0x71736c, alpha: 0.94), stroke: NSColor(hex: 0x102b24, alpha: 0.55), lineWidth: 1.5)
    context.setShadow(offset: .zero, blur: 0, color: nil)

    drawSpruce(at: NSPoint(x: menu.minX + 32, y: menu.minY + 26), size: 25, color: NSColor(hex: 0xdce6da, alpha: 0.72))
    drawText("NodeSnoop", x: menu.minX + 70, y: menu.minY + 20, width: 220, size: 24, weight: .semibold, color: NSColor(hex: 0xdce6da, alpha: 0.72))
    drawText("3 projects, 6 Node processes", x: menu.minX + 30, y: menu.minY + 72, width: 360, size: 22, weight: .medium, color: NSColor(hex: 0xdce6da, alpha: 0.64))
    line(from: NSPoint(x: menu.minX + 28, y: menu.minY + 118), to: NSPoint(x: menu.maxX - 28, y: menu.minY + 118), color: NSColor.white.withAlphaComponent(0.16))

    drawText("LOCALHOST PROJECTS", x: menu.minX + 34, y: menu.minY + 144, width: 360, size: 18, weight: .bold, color: NSColor(hex: 0xdce6da, alpha: 0.52))
    drawMenuRow(x: menu.minX + 42, y: menu.minY + 188, width: menu.width - 92, title: "web", detail: "LIKELY :3000  Next.js  2 procs", selected: true)
    drawMenuRow(x: menu.minX + 42, y: menu.minY + 240, width: menu.width - 92, title: "dabble-development-library...", detail: "LIKELY :3000  Next.js  3 procs")

    line(from: NSPoint(x: menu.minX + 28, y: menu.minY + 304), to: NSPoint(x: menu.maxX - 28, y: menu.minY + 304), color: NSColor.white.withAlphaComponent(0.16))
    drawText("OTHER PROJECTS", x: menu.minX + 34, y: menu.minY + 330, width: 260, size: 18, weight: .bold, color: NSColor(hex: 0xdce6da, alpha: 0.52))
    drawMenuRow(x: menu.minX + 42, y: menu.minY + 374, width: menu.width - 92, title: "backend-v3", detail: "tsx  1 Node process")

    line(from: NSPoint(x: menu.minX + 28, y: menu.minY + 438), to: NSPoint(x: menu.maxX - 28, y: menu.minY + 438), color: NSColor.white.withAlphaComponent(0.16))
    drawText("BULK ACTIONS", x: menu.minX + 34, y: menu.minY + 464, width: 260, size: 18, weight: .bold, color: NSColor(hex: 0xdce6da, alpha: 0.52))
    drawSubmenuRow(x: menu.minX + 42, y: menu.minY + 506, width: 420, text: "Kill All Node.js Processes")
    drawSubmenuRow(x: menu.minX + 42, y: menu.minY + 550, width: 180, text: "Refresh")

    let submenu = NSRect(x: 214, y: 224, width: 510, height: 574)
    context.setShadow(offset: CGSize(width: 0, height: 20), blur: 30, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    roundedRect(submenu, radius: 14, fill: NSColor(hex: 0x777872, alpha: 0.96), stroke: NSColor(hex: 0x182d27, alpha: 0.55), lineWidth: 1.5)
    context.setShadow(offset: .zero, blur: 0, color: nil)

    drawText("web", x: submenu.minX + 28, y: submenu.minY + 24, width: 180, size: 25, weight: .semibold, color: NSColor(hex: 0xf4f4ef))
    drawText("Likely localhost :3000", x: submenu.minX + 28, y: submenu.minY + 68, width: 280, size: 22, weight: .medium, color: NSColor(hex: 0xf4f4ef, alpha: 0.82))
    drawText("Next.js - next dev", x: submenu.minX + 28, y: submenu.minY + 108, width: 300, size: 22, weight: .medium, color: NSColor(hex: 0xf4f4ef, alpha: 0.82))
    drawText("2 Node processes", x: submenu.minX + 28, y: submenu.minY + 148, width: 260, size: 22, weight: .medium, color: NSColor(hex: 0xf4f4ef, alpha: 0.82))
    drawMonoText("~/Code/quarter-ag/quarter-ag-main/web", x: submenu.minX + 28, y: submenu.minY + 190, width: submenu.width - 56, size: 17, weight: .medium, color: NSColor(hex: 0xf4f4ef, alpha: 0.72))
    line(from: NSPoint(x: submenu.minX + 28, y: submenu.minY + 238), to: NSPoint(x: submenu.maxX - 28, y: submenu.minY + 238), color: NSColor.white.withAlphaComponent(0.16))

    drawSubmenuRow(x: submenu.minX + 28, y: submenu.minY + 268, width: 260, text: "Open Localhost", emphasis: true)
    drawSubmenuRow(x: submenu.minX + 28, y: submenu.minY + 312, width: 300, text: "Open Terminal at Project")
    drawSubmenuRow(x: submenu.minX + 28, y: submenu.minY + 356, width: 260, text: "Copy Localhost URL")
    drawSubmenuRow(x: submenu.minX + 28, y: submenu.minY + 400, width: 260, text: "Stop Project")

    line(from: NSPoint(x: submenu.minX + 28, y: submenu.minY + 450), to: NSPoint(x: submenu.maxX - 28, y: submenu.minY + 450), color: NSColor.white.withAlphaComponent(0.16))
    drawText("PROCESSES", x: submenu.minX + 28, y: submenu.minY + 478, width: 180, size: 18, weight: .bold, color: NSColor(hex: 0xdce6da, alpha: 0.52))
    drawSubmenuRow(x: submenu.minX + 28, y: submenu.minY + 520, width: 320, text: "PID 52105  next dev")
    drawChevron(x: submenu.maxX - 44, y: submenu.minY + 524, color: NSColor(hex: 0xf4f4ef))

    return true
}

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not render PNG")
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL, options: .atomic)

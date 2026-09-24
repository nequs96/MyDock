import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Pass the destination .iconset directory\n", stderr)
    exit(2)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func render(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                        bitsPerSample: 8, samplesPerPixel: 4,
                                        hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let transform = AffineTransform(scaleByX: CGFloat(pixelSize) / 1_024,
                                    byY: CGFloat(pixelSize) / 1_024)
    NSAffineTransform(transform: transform).concat()

    let background = NSBezierPath(roundedRect: NSRect(x: 54, y: 54, width: 916, height: 916),
                                  xRadius: 212, yRadius: 212)
    background.addClip()
    NSGradient(starting: color(0.15, 0.24, 0.69),
               ending: color(0.05, 0.67, 0.74))?.draw(in: background, angle: -35)

    rounded(NSRect(x: 130, y: 155, width: 764, height: 204), radius: 102,
            fill: color(1, 1, 1, 0.21))
    let shelfBorder = NSBezierPath(roundedRect: NSRect(x: 130, y: 155, width: 764, height: 204),
                                   xRadius: 102, yRadius: 102)
    shelfBorder.lineWidth = 8
    color(1, 1, 1, 0.48).setStroke()
    shelfBorder.stroke()

    let tiles: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
        (216, 308, 162, 254, color(0.95, 0.97, 1.0)),
        (431, 342, 162, 300, color(1.0, 1.0, 1.0)),
        (646, 308, 162, 254, color(0.94, 0.98, 1.0))
    ]
    for tile in tiles {
        rounded(NSRect(x: tile.0, y: tile.1, width: tile.2, height: tile.3),
                radius: 40, fill: tile.4)
    }
    rounded(NSRect(x: 250, y: 468, width: 94, height: 12), radius: 6,
            fill: color(0.18, 0.33, 0.73, 0.48))
    rounded(NSRect(x: 250, y: 437, width: 70, height: 12), radius: 6,
            fill: color(0.18, 0.33, 0.73, 0.30))
    rounded(NSRect(x: 464, y: 535, width: 96, height: 22), radius: 11,
            fill: color(0.10, 0.58, 0.74, 0.75))
    rounded(NSRect(x: 464, y: 491, width: 72, height: 14), radius: 7,
            fill: color(0.10, 0.58, 0.74, 0.38))
    rounded(NSRect(x: 680, y: 468, width: 94, height: 12), radius: 6,
            fill: color(0.16, 0.44, 0.70, 0.46))
    rounded(NSRect(x: 680, y: 437, width: 56, height: 12), radius: 6,
            fill: color(0.16, 0.44, 0.70, 0.28))

    for x in [297.0, 512.0, 727.0] {
        color(1, 1, 1, 0.88).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 9, y: 222, width: 18, height: 18)).fill()
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1_024)
]
for (name, size) in outputs {
    try render(pixelSize: size).write(to: destination.appendingPathComponent(name), options: .atomic)
}

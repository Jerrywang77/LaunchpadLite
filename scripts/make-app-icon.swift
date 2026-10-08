import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let canvasSize = 1024

guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create drawing context\n", stderr)
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

func fillRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    color: CGColor
) {
    context.addPath(
        CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    )
    context.setFillColor(color)
    context.fillPath()
}

let panelRect = CGRect(x: 88, y: 88, width: 848, height: 848)
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 38,
    color: CGColor(gray: 0, alpha: 0.30)
)
fillRoundedRect(panelRect, radius: 188, color: CGColor(gray: 1, alpha: 1))
context.restoreGState()

context.addPath(
    CGPath(
        roundedRect: panelRect,
        cornerWidth: 188,
        cornerHeight: 188,
        transform: nil
    )
)
context.setStrokeColor(CGColor(gray: 0.86, alpha: 1))
context.setLineWidth(4)
context.strokePath()

let tileSize: CGFloat = 170
let gap: CGFloat = 58
let startX: CGFloat = 198
let rowY: [CGFloat] = [182, 410, 638]
let colors: [[CGColor]] = [
    [
        CGColor(red: 0.18, green: 0.50, blue: 0.96, alpha: 1),
        CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        CGColor(red: 0.98, green: 0.22, blue: 0.38, alpha: 1)
    ],
    [
        CGColor(red: 1.00, green: 0.59, blue: 0.00, alpha: 1),
        CGColor(red: 0.68, green: 0.34, blue: 0.86, alpha: 1),
        CGColor(red: 0.56, green: 0.57, blue: 0.60, alpha: 1)
    ],
    [
        CGColor(red: 0.20, green: 0.68, blue: 0.95, alpha: 1),
        CGColor(red: 0.40, green: 0.83, blue: 0.56, alpha: 1),
        CGColor(red: 1.00, green: 0.38, blue: 0.52, alpha: 1)
    ]
]

for (row, y) in rowY.enumerated() {
    for (column, color) in colors[row].enumerated() {
        let x = startX + (tileSize + gap) * CGFloat(column)
        fillRoundedRect(
            CGRect(x: x, y: y, width: tileSize, height: tileSize),
            radius: 36,
            color: color
        )
    }
}

guard
    let cgImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outputPath) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("Unable to render icon\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, cgImage, nil)

guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write icon\n", stderr)
    exit(1)
}

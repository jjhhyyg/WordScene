import AppKit
import Foundation

let sourceURL = URL(fileURLWithPath: "WordScene/Resources/Brand/WordSceneLogo.png")
let outputDirectory = URL(fileURLWithPath: "WordScene/Resources/Assets.xcassets/AppIcon.appiconset")
let sourceCropInset: CGFloat = 28

let iconSizes: [(filename: String, pixels: Int)] = [
    ("Icon-1024.png", 1024),
    ("Icon-20@2x.png", 40),
    ("Icon-20@3x.png", 60),
    ("Icon-29@2x.png", 58),
    ("Icon-29@3x.png", 87),
    ("Icon-40@2x.png", 80),
    ("Icon-40@3x.png", 120),
    ("Icon-60@2x.png", 120),
    ("Icon-60@3x.png", 180),
    ("Icon-20-ipad.png", 20),
    ("Icon-20-ipad@2x.png", 40),
    ("Icon-29-ipad.png", 29),
    ("Icon-29-ipad@2x.png", 58),
    ("Icon-40-ipad.png", 40),
    ("Icon-40-ipad@2x.png", 80),
    ("Icon-76-ipad.png", 76),
    ("Icon-76-ipad@2x.png", 152),
    ("Icon-83_5-ipad@2x.png", 167),
    ("Icon-16-mac.png", 16),
    ("Icon-16-mac@2x.png", 32),
    ("Icon-32-mac.png", 32),
    ("Icon-32-mac@2x.png", 64),
    ("Icon-128-mac.png", 128),
    ("Icon-128-mac@2x.png", 256),
    ("Icon-256-mac.png", 256),
    ("Icon-256-mac@2x.png", 512),
    ("Icon-512-mac.png", 512)
]

enum IconError: LocalizedError {
    case missingSource(URL)
    case bitmapCreationFailed(Int)
    case pngEncodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSource(let url):
            return "Missing source logo: \(url.path)"
        case .bitmapCreationFailed(let pixels):
            return "Could not create \(pixels)x\(pixels) bitmap."
        case .pngEncodingFailed(let filename):
            return "Could not encode PNG for \(filename)."
        }
    }
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw IconError.missingSource(sourceURL)
}

func resizedPNGData(from image: NSImage, pixels: Int, filename: String) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconError.bitmapCreationFailed(pixels)
    }

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let sourceRect = NSRect(
        x: sourceCropInset,
        y: sourceCropInset,
        width: image.size.width - sourceCropInset * 2,
        height: image.size.height - sourceCropInset * 2
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: canvas, from: sourceRect, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.pngEncodingFailed(filename)
    }

    return data
}

for icon in iconSizes {
    let data = try resizedPNGData(from: sourceImage, pixels: icon.pixels, filename: icon.filename)
    try data.write(to: outputDirectory.appendingPathComponent(icon.filename))
}

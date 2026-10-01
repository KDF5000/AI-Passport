import AppKit
import Foundation

private let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: render_ios_brand_assets <source.svg> <ios-dir>\n", stderr)
    exit(2)
}

private let sourceURL = URL(fileURLWithPath: args[1])
private let iosURL = URL(fileURLWithPath: args[2])
private let iconSetURL = iosURL
    .appendingPathComponent("Runner/Assets.xcassets/AppIcon.appiconset")
private let launchSetURL = iosURL
    .appendingPathComponent("Runner/Assets.xcassets/LaunchImage.imageset")

guard let svgImage = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load SVG source\n", stderr)
    exit(3)
}

private func writePNG(_ image: NSImage, size: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "BrandAssets", code: 1)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BrandAssets", code: 2)
    }
    try data.write(to: url, options: .atomic)

    // App Store icons must not contain an alpha channel. Converting through a
    // maximum-quality JPEG flattens the already opaque artwork, then restores
    // PNG as the asset-catalog format.
    let temporaryJPEG = url.deletingPathExtension().appendingPathExtension("jpg")
    let toJPEG = Process()
    toJPEG.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    toJPEG.arguments = [
        "-s", "format", "jpeg",
        "-s", "formatOptions", "100",
        url.path,
        "--out", temporaryJPEG.path,
    ]
    try toJPEG.run()
    toJPEG.waitUntilExit()
    guard toJPEG.terminationStatus == 0 else {
        throw NSError(domain: "BrandAssets", code: 3)
    }

    let toPNG = Process()
    toPNG.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    toPNG.arguments = ["-s", "format", "png", temporaryJPEG.path, "--out", url.path]
    try toPNG.run()
    toPNG.waitUntilExit()
    try? FileManager.default.removeItem(at: temporaryJPEG)
    guard toPNG.terminationStatus == 0 else {
        throw NSError(domain: "BrandAssets", code: 4)
    }
}

private let icons: [(String, Int)] = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

do {
    for (name, size) in icons {
        try writePNG(svgImage, size: size, to: iconSetURL.appendingPathComponent(name))
    }
    try writePNG(svgImage, size: 168, to: launchSetURL.appendingPathComponent("LaunchImage.png"))
    try writePNG(svgImage, size: 336, to: launchSetURL.appendingPathComponent("LaunchImage@2x.png"))
    try writePNG(svgImage, size: 504, to: launchSetURL.appendingPathComponent("LaunchImage@3x.png"))
} catch {
    fputs("Failed to render brand assets: \(error)\n", stderr)
    exit(4)
}

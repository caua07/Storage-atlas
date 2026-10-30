#!/usr/bin/env swift
import AppKit
import Foundation

// Render our four-rectangle vector mark directly at every macOS icon resolution.
// This deliberately supports the simple AppIcon.svg artwork, not arbitrary SVG.
struct IconError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct IconRectangle {
    let bounds: NSRect
    let radius: CGFloat
    let color: NSColor

    init(_ element: XMLElement) throws {
        func number(_ name: String, fallback: Double? = nil) throws -> CGFloat {
            if let text = element.attribute(forName: name)?.stringValue, let value = Double(text) {
                return CGFloat(value)
            }
            if let fallback { return CGFloat(fallback) }
            throw IconError(message: "Missing numeric icon attribute: \(name)")
        }
        let x = try number("x"), y = try number("y")
        let width = try number("width"), height = try number("height")
        bounds = NSRect(x: x, y: 1024 - y - height, width: width, height: height)
        radius = try number("rx", fallback: 0)
        let fill = element.attribute(forName: "fill")?.stringValue ?? ""
        guard fill.count == 7, fill.first == "#", let hex = UInt32(fill.dropFirst(), radix: 16) else {
            throw IconError(message: "Expected a six-digit hex icon fill")
        }
        color = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                        green: CGFloat((hex >> 8) & 255) / 255,
                        blue: CGFloat(hex & 255) / 255,
                        alpha: try number("opacity", fallback: 1))
    }
}

do {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let resources = root.appendingPathComponent("Resources", isDirectory: true)
    let document = try XMLDocument(contentsOf: resources.appendingPathComponent("AppIcon.svg"))
    let nodes = try document.nodes(forXPath: "//*[local-name()='rect']")
    let rectangles = try nodes.compactMap { $0 as? XMLElement }.map(IconRectangle.init)
    guard rectangles.count == 4 else { throw IconError(message: "Expected the four Atlas icon rectangles") }

    let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw IconError(message: "Cannot create \(pixels)px icon bitmap")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            for rectangle in rectangles {
                rectangle.color.setFill()
                NSBezierPath(roundedRect: rectangle.bounds, xRadius: rectangle.radius, yRadius: rectangle.radius).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw IconError(message: "Cannot encode \(pixels)px icon")
            }
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
        }
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["--convert", "icns", iconset.path, "--output", resources.appendingPathComponent("AppIcon.icns").path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { throw IconError(message: "iconutil failed") }
    print("Generated Resources/AppIcon.icns (16–1024px)")
} catch {
    FileHandle.standardError.write(Data("Icon generation: \(error.localizedDescription)\n".utf8))
    exit(1)
}

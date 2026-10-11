// Draws Dustbunny's app icon entirely in code and writes Resources/AppIcon.icns.
// No external images are used, so anyone can see exactly what the icon is made of.
//
// Usage: swift scripts/make-icon.swift            (writes Resources/AppIcon.icns)
//        swift scripts/make-icon.swift preview.png (also writes a 1024px PNG preview)

import AppKit
import SwiftUI

let pink = Color(red: 0.95, green: 0.52, blue: 0.66)
let lilac = Color(red: 0.73, green: 0.67, blue: 0.96)
let ink = Color(red: 0.16, green: 0.12, blue: 0.22)

struct IconArt: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 1024 // design on a 1024pt grid
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }

            // macOS icon grid: 824pt rounded square centred in 1024pt.
            let tile = Path(roundedRect: r(100, 100, 824, 824), cornerRadius: 185 * s, style: .continuous)

            // Soft drop shadow under the tile.
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 18 * s, x: 0, y: 12 * s))
                layer.fill(tile, with: .color(.white))
            }

            context.drawLayer { tileLayer in
                tileLayer.clip(to: tile)

                // Background: lilac to pink, with soft glows.
                tileLayer.fill(tile, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.80, green: 0.74, blue: 1.0), Color(red: 1.0, green: 0.68, blue: 0.80)]),
                    startPoint: p(150, 120), endPoint: p(880, 920)))
                tileLayer.fill(Path(ellipseIn: r(40, 40, 700, 620)), with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]), center: p(300, 250), startRadius: 0, endRadius: 420 * s))
                tileLayer.fill(Path(ellipseIn: r(450, 520, 600, 520)), with: .radialGradient(
                    Gradient(colors: [pink.opacity(0.55), pink.opacity(0)]), center: p(820, 860), startRadius: 0, endRadius: 360 * s))

                // Frosted glass disc behind the bunny.
                let disc = Path(ellipseIn: r(212, 232, 600, 600))
                tileLayer.fill(disc, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.42), .white.opacity(0.12)]), startPoint: p(300, 240), endPoint: p(720, 830)))
                tileLayer.stroke(disc, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.9), .white.opacity(0.15)]), startPoint: p(300, 240), endPoint: p(720, 830)),
                    lineWidth: 5 * s)

                // Shadow on the "floor".
                tileLayer.drawLayer { shadow in
                    shadow.addFilter(.blur(radius: 18 * s))
                    shadow.fill(Path(ellipseIn: r(330, 760, 364, 56)), with: .color(ink.opacity(0.22)))
                }

                let fur = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [.white, Color(white: 0.93), Color(red: 0.80, green: 0.78, blue: 0.86)]),
                    startPoint: p(380, 300), endPoint: p(640, 800))

                // Ears (behind the body), with pink insides.
                for (cx, angle) in [(425.0, -14.0), (600.0, 12.0)] {
                    tileLayer.drawLayer { ear in
                        ear.translateBy(x: cx * s, y: 400 * s)
                        ear.rotate(by: .degrees(angle))
                        ear.fill(Path(ellipseIn: r(-52, -165, 104, 250)), with: fur)
                        ear.fill(Path(ellipseIn: r(-27, -128, 54, 175)), with: .color(pink.opacity(0.75)))
                    }
                }

                // Fluffy body: a ring of puffs around a soft core.
                var body = Path()
                body.addEllipse(in: r(312, 440, 400, 320))
                // Uneven puff sizes (a fixed pattern, so the icon is identical every time it's generated).
                let wobble: [Double] = [0, 9, 3, 12, 5, 1, 10, 4, 13, 2, 8, 6]
                let puffs = 26
                for i in 0..<puffs {
                    let a = Double(i) / Double(puffs) * 2 * .pi
                    let radius = 44.0 + wobble[i % wobble.count]
                    let cx = 512 + cos(a) * (190 + wobble[(i + 5) % wobble.count])
                    let cy = 600 + sin(a) * (158 + wobble[(i + 3) % wobble.count] * 0.6)
                    body.addEllipse(in: r(cx - radius, cy - radius, radius * 2, radius * 2))
                }
                // Stray wisps of fluff.
                for (x, y, d) in [(300.0, 530.0, 26.0), (726.0, 560.0, 22.0), (330.0, 708.0, 20.0), (700.0, 712.0, 24.0)] {
                    body.addEllipse(in: r(x - d / 2, y - d / 2, d, d))
                }
                tileLayer.drawLayer { b in
                    b.addFilter(.shadow(color: Color(red: 0.45, green: 0.30, blue: 0.55).opacity(0.25), radius: 10 * s, x: 0, y: 8 * s))
                    b.fill(body, with: fur)
                }

                // Face.
                for x in [452.0, 572.0] {
                    tileLayer.fill(Path(ellipseIn: r(x - 25, 562, 50, 62)), with: .color(ink))
                    tileLayer.fill(Path(ellipseIn: r(x - 14, 572, 18, 20)), with: .color(.white))
                    tileLayer.fill(Path(ellipseIn: r(x + 4, 600, 8, 8)), with: .color(.white.opacity(0.7)))
                }
                for x in [400.0, 624.0] {
                    tileLayer.fill(Path(ellipseIn: r(x - 34, 640, 68, 34)), with: .color(pink.opacity(0.55)))
                }
                tileLayer.fill(Path(ellipseIn: r(498, 632, 28, 20)), with: .color(pink))
                var mouth = Path()
                mouth.move(to: p(486, 660))
                mouth.addQuadCurve(to: p(512, 664), control: p(498, 676))
                mouth.addQuadCurve(to: p(538, 660), control: p(526, 676))
                tileLayer.stroke(mouth, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))

                // Sparkles: freshly cleaned.
                func sparkle(_ cx: Double, _ cy: Double, _ size: Double, _ opacity: Double) {
                    var star = Path()
                    let c = p(cx, cy)
                    let k = size * s
                    star.move(to: CGPoint(x: c.x, y: c.y - k))
                    star.addQuadCurve(to: CGPoint(x: c.x + k, y: c.y), control: c)
                    star.addQuadCurve(to: CGPoint(x: c.x, y: c.y + k), control: c)
                    star.addQuadCurve(to: CGPoint(x: c.x - k, y: c.y), control: c)
                    star.addQuadCurve(to: CGPoint(x: c.x, y: c.y - k), control: c)
                    tileLayer.fill(star, with: .color(.white.opacity(opacity)))
                }
                sparkle(282, 300, 58, 0.95)
                sparkle(752, 268, 40, 0.9)
                sparkle(790, 470, 26, 0.8)
                sparkle(236, 520, 22, 0.7)

                // Glass sheen across the top of the tile.
                tileLayer.fill(Path(roundedRect: r(100, 100, 824, 380), cornerRadius: 185 * s, style: .continuous), with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.28), .white.opacity(0)]), startPoint: p(512, 100), endPoint: p(512, 480)))
            }

            // Thin bright rim, like the edge of a glass tile.
            context.stroke(tile, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.75), .white.opacity(0.1)]), startPoint: p(512, 100), endPoint: p(512, 924)),
                lineWidth: 3 * s)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render(pixels: Int) -> Data {
    let renderer = ImageRenderer(content: IconArt())
    renderer.scale = Double(pixels) / 1024
    guard let cgImage = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    return png
}

@main
struct MakeIcon {
    static func main() throws {
        try MainActor.assumeIsolated {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Dustbunny-\(UUID().uuidString).iconset")
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: iconset) }

            for points in [16, 32, 128, 256, 512] {
                try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
                try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
            }

            let output = root.appendingPathComponent("Resources/AppIcon.icns")
            let iconutil = Process()
            iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
            try iconutil.run()
            iconutil.waitUntilExit()
            guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
            print("Wrote \(output.path)")

            if CommandLine.arguments.count > 1 {
                try render(pixels: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                print("Wrote preview \(CommandLine.arguments[1])")
            }
        }
    }
}

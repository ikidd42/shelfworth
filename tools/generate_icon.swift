#!/usr/bin/env swift
// Generates the app icon set and launch motif from the same classical
// marbling used in the app (see Library/Utilities/Marbling.swift).
//
// Run from anywhere:  swift tools/generate_icon.swift
// No dependencies — CoreGraphics only. Outputs into Library/Assets.xcassets.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Deterministic RNG

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + unit() * (hi - lo) }
}

// MARK: - Marbling (mirrors the in-app renderer)

typealias RGB = (Double, Double, Double)

struct MarblePalette {
    let paper: RGB
    let inks: [RGB]   // vein (darkest), mid, light, accent
    let gilt: RGB
}

let forestMarble = MarblePalette(
    paper: (0.91, 0.90, 0.79),
    inks: [(0.11, 0.25, 0.18), (0.47, 0.59, 0.45), (0.91, 0.90, 0.79), (0.55, 0.42, 0.20)],
    gilt: (0.83, 0.72, 0.42)
)

let espressoMarble = MarblePalette(
    paper: (0.13, 0.10, 0.06),
    inks: [(0.30, 0.12, 0.09), (0.33, 0.27, 0.17), (0.22, 0.18, 0.11), (0.14, 0.17, 0.24)],
    gilt: (0.62, 0.47, 0.26)
)

let indigoMarble = MarblePalette(
    paper: (0.90, 0.89, 0.82),
    inks: [(0.13, 0.19, 0.33), (0.42, 0.50, 0.64), (0.90, 0.89, 0.82), (0.47, 0.19, 0.14)],
    gilt: (0.80, 0.72, 0.50)
)

enum Op {
    case drop(cx: Double, cy: Double, r: Double, ink: Int)
    case comb(spacing: Double, phase: Double, z: Double, lambda: Double, dir: Double)
}

func invert(_ p: inout (x: Double, y: Double), _ op: Op) -> Int? {
    switch op {
    case let .drop(cx, cy, r, ink):
        let dx = p.x - cx, dy = p.y - cy
        let dist2 = dx * dx + dy * dy
        let r2 = r * r
        if dist2 <= r2 { return ink }
        let scale = (1 - r2 / dist2).squareRoot()
        p.x = cx + dx * scale
        p.y = cy + dy * scale
        return nil
    case let .comb(s, phase, z, lambda, dir):
        let t = (p.x - phase) / s
        let frac = t - t.rounded(.down)
        let d = abs(frac - 0.5) * s
        let dTine = s / 2 - d
        p.y -= dir * z * lambda / (dTine + lambda)
        return nil
    }
}

func stoneOps(rng: inout SplitMix, w: Double, h: Double) -> [Op] {
    var ops: [Op] = []
    let counts = [(90, 40.0, 78.0), (150, 20.0, 44.0), (140, 9.0, 22.0)]
    var inkStep = 0
    for (n, rLo, rHi) in counts {
        for _ in 0..<n {
            let ink = [0, 1, 2, 1, 0, 2, 3, 1][inkStep % 8]
            inkStep += 1
            ops.append(.drop(cx: rng.range(-40, w + 40), cy: rng.range(-40, h + 40),
                             r: rng.range(rLo, rHi), ink: ink))
        }
    }
    return ops
}

func nonpareilOps(rng: inout SplitMix) -> [Op] {
    [.comb(spacing: 34, phase: rng.range(0, 34), z: 240, lambda: 22, dir: 1)]
}

func lattice(_ ix: Int, _ iy: Int, _ seed: UInt64) -> Double {
    var h = UInt64(bitPattern: Int64(ix)) &* 0x9E3779B97F4A7C15
    h &+= UInt64(bitPattern: Int64(iy)) &* 0xC2B2AE3D27D4EB4F
    h ^= seed
    h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
    h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
    return Double((h ^ (h >> 31)) >> 11) / Double(1 << 53)
}

func smootherstep(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

func valueNoise(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
    let ix = Int(x.rounded(.down)), iy = Int(y.rounded(.down))
    let fx = smootherstep(x - Double(ix)), fy = smootherstep(y - Double(iy))
    let a = lattice(ix, iy, seed), b = lattice(ix + 1, iy, seed)
    let c = lattice(ix, iy + 1, seed), d = lattice(ix + 1, iy + 1, seed)
    let ab = a + (b - a) * fx, cd = c + (d - c) * fx
    return ab + (cd - ab) * fy
}

func fbm(_ x: Double, _ y: Double, _ octaves: Int, _ seed: UInt64) -> Double {
    var v = 0.0, amp = 0.5, freq = 1.0
    for i in 0..<octaves {
        v += amp * valueNoise(x * freq, y * freq, seed &+ UInt64(i) &* 0x85EBCA6B)
        amp *= 0.5; freq *= 2
    }
    return v
}

func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
}

/// Renders a marbled sheet. No paper grain here (unlike the app) — grain is
/// invisible at icon sizes and roughly triples the PNG payload.
func marbleSheet(palette: MarblePalette, pattern: String, seed: UInt64,
                 w: Int, h: Int, unitsPerPixel: Double, veins: Bool) -> CGImage {
    var rng = SplitMix(seed: seed)
    let sheetW = Double(w) * unitsPerPixel, sheetH = Double(h) * unitsPerPixel
    let ops = pattern == "stone" ? stoneOps(rng: &rng, w: sheetW, h: sheetH)
                                 : nonpareilOps(rng: &rng)
    let banded = pattern != "stone"
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    for py in 0..<h {
        for px in 0..<w {
            var p = (x: Double(px) * unitsPerPixel, y: Double(py) * unitsPerPixel)
            let wob = banded ? 2.2 : 6.0
            p.x += (fbm(p.y * 0.012, p.x * 0.012, 3, seed &+ 3) - 0.5) * 2 * wob
            p.y += (fbm(p.x * 0.011 + 9.7, p.y * 0.011, 3, seed &+ 5) - 0.5) * 2 * wob
            var ink: Int? = nil
            for op in ops.reversed() {
                if let hit = invert(&p, op) { ink = hit; break }
            }
            var c: RGB
            if let ink {
                c = palette.inks[ink]
            } else if banded {
                let bandH = 34.0
                let breathe = (valueNoise(p.y * 0.02, 3.7, seed &+ 21) - 0.5) * 8
                let idx = Int(((p.y + breathe) / bandH).rounded(.down))
                let cycle = [0, 1, 2, 3, 2, 1]
                c = palette.inks[cycle[((idx % cycle.count) + cycle.count) % cycle.count]]
            } else {
                c = palette.paper
            }
            if veins {
                let vx = Double(px) * 0.016, vy = Double(py) * 0.016
                let ridge = 1 - abs(2 * fbm(vx, vy, 4, seed &+ 11) - 1)
                if ridge > 0.965 {
                    c = mix(c, palette.gilt, 0.55 + 0.35 * (ridge - 0.965) / 0.035)
                }
            }
            let i = (py * w + px) * 4
            pixels[i] = UInt8(clamping: Int(c.0 * 255))
            pixels[i + 1] = UInt8(clamping: Int(c.1 * 255))
            pixels[i + 2] = UInt8(clamping: Int(c.2 * 255))
            pixels[i + 3] = 255
        }
    }
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent)!
}

// MARK: - Drawing helpers

func rgbColor(_ c: RGB, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: c.0, green: c.1, blue: c.2, alpha: alpha)
}

func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

func makeContext(_ size: Int, _ height: Int? = nil) -> CGContext {
    CGContext(data: nil, width: size, height: height ?? size,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Radial vignette darkening toward the edges.
func vignette(_ ctx: CGContext, size: CGFloat, color: CGColor, strength: CGFloat) {
    let colors = [color.copy(alpha: 0)!, color.copy(alpha: strength)!] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: colors, locations: [0.45, 1.0])!
    let center = CGPoint(x: size / 2, y: size / 2)
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: size * 0.72, options: [])
}

/// The Athenaeum double gilt frame.
func giltFrame(_ ctx: CGContext, size: CGFloat, gilt: RGB,
               outerAlpha: CGFloat, innerAlpha: CGFloat) {
    let inset: CGFloat = 64
    ctx.setLineWidth(5)
    ctx.setStrokeColor(rgbColor(gilt, outerAlpha))
    ctx.addPath(roundedPath(CGRect(x: inset, y: inset, width: size - 2 * inset,
                                   height: size - 2 * inset), 18))
    ctx.strokePath()
    let i2 = inset + 19
    ctx.setLineWidth(2)
    ctx.setStrokeColor(rgbColor(gilt, innerAlpha))
    ctx.addPath(roundedPath(CGRect(x: i2, y: i2, width: size - 2 * i2,
                                   height: size - 2 * i2), 12))
    ctx.strokePath()
}

struct Spine {
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat
    let top: UInt32
    let bottom: UInt32
}

let iconSpines = [
    Spine(x: 308, width: 112, height: 434, top: 0x844133, bottom: 0x51251C),   // oxblood
    Spine(x: 444, width: 136, height: 500, top: 0x394D66, bottom: 0x212E40),   // navy
    Spine(x: 604, width: 112, height: 452, top: 0xB28334, bottom: 0x74521D),   // ochre
]

/// Cloth book spines with gilt bands and a soft shadow.
func drawSpines(_ ctx: CGContext, baseline: CGFloat, spines: [Spine],
                gilt: RGB, giltAlpha: CGFloat, scale: CGFloat = 1,
                marbledIndex: Int? = nil, marble: CGImage? = nil) {
    for (index, spine) in spines.enumerated() {
        let rect = CGRect(x: spine.x * scale, y: baseline,
                          width: spine.width * scale, height: spine.height * scale)
        let path = roundedPath(rect, 18 * scale)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale),
                      blur: 16 * scale, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(path)
        ctx.setFillColor(hex(spine.bottom))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if index == marbledIndex, let marble {
            ctx.draw(marble, in: rect)
        } else {
            let colors = [hex(spine.top), hex(spine.bottom)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        }
        // Gilt bands near head and tail
        ctx.setFillColor(rgbColor(gilt, giltAlpha))
        for band: CGFloat in [rect.maxY - 78 * scale, rect.maxY - 106 * scale,
                              rect.minY + 64 * scale, rect.minY + 92 * scale] {
            ctx.fill(CGRect(x: rect.minX, y: band, width: rect.width, height: 6 * scale))
        }
        ctx.restoreGState()
    }
}

/// Quantize to 6 bits/channel before saving: invisible under marble texture,
/// but collapses the vignette's per-pixel gradient enough for PNG to compress.
func posterize(_ ctx: CGContext) {
    guard let data = ctx.data else { return }
    let buf = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
    for i in 0..<(ctx.bytesPerRow * ctx.height) {
        buf[i] = buf[i] & 0b1111_1100
    }
}

func save(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int ?? 0
    print("wrote \(path) (\(bytes / 1024)KB)")
}

// MARK: - Variants

func iconLight(_ path: String) {
    let ctx = makeContext(1024)
    let marble = marbleSheet(palette: forestMarble, pattern: "stone", seed: 19,
                             w: 1024, h: 1024, unitsPerPixel: 1.0, veins: true)
    ctx.draw(marble, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    vignette(ctx, size: 1024, color: hex(0x1B2C20), strength: 0.45)
    giltFrame(ctx, size: 1024, gilt: forestMarble.gilt, outerAlpha: 0.9, innerAlpha: 0.55)
    drawSpines(ctx, baseline: 262, spines: iconSpines,
               gilt: forestMarble.gilt, giltAlpha: 0.95)
    posterize(ctx)
    save(ctx.makeImage()!, path)
}

func iconDark(_ path: String) {
    let ctx = makeContext(1024)
    let marble = marbleSheet(palette: espressoMarble, pattern: "stone", seed: 42,
                             w: 1024, h: 1024, unitsPerPixel: 1.0, veins: true)
    ctx.draw(marble, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    vignette(ctx, size: 1024, color: hex(0x0B0805), strength: 0.55)
    giltFrame(ctx, size: 1024, gilt: espressoMarble.gilt, outerAlpha: 0.9, innerAlpha: 0.55)
    drawSpines(ctx, baseline: 262, spines: iconSpines,
               gilt: espressoMarble.gilt, giltAlpha: 0.9)
    posterize(ctx)
    save(ctx.makeImage()!, path)
}

func iconTinted(_ path: String) {
    let ctx = makeContext(1024)
    let cream: RGB = (0.94, 0.91, 0.84)
    giltFrame(ctx, size: 1024, gilt: cream, outerAlpha: 1.0, innerAlpha: 0.6)
    for spine in iconSpines {
        let rect = CGRect(x: spine.x, y: 262, width: spine.width, height: spine.height)
        ctx.addPath(roundedPath(rect, 18))
        ctx.setFillColor(rgbColor(cream))
        ctx.fillPath()
        // Cut the band slots out so the tint shows structure
        ctx.setBlendMode(.clear)
        for band: CGFloat in [rect.maxY - 78, rect.maxY - 106, rect.minY + 64, rect.minY + 92] {
            ctx.fill(CGRect(x: rect.minX, y: band, width: rect.width, height: 6))
        }
        ctx.setBlendMode(.normal)
    }
    save(ctx.makeImage()!, path)
}

func launchMotif(_ path: String) {
    let ctx = makeContext(360, 540)
    let scale: CGFloat = 0.35
    // Center the spine cluster horizontally: icon spines span x 308–716
    let clusterWidth = (716.0 - 308.0) * scale
    let shift = (360 - clusterWidth) / 2 - 308 * scale
    let shifted = iconSpines.map {
        Spine(x: $0.x + shift / scale, width: $0.width, height: $0.height,
              top: $0.top, bottom: $0.bottom)
    }
    let marble = marbleSheet(palette: indigoMarble, pattern: "nonpareil", seed: 7,
                             w: 48, h: 175, unitsPerPixel: 2.2, veins: false)
    drawSpines(ctx, baseline: 150, spines: shifted, gilt: forestMarble.gilt,
               giltAlpha: 0.95, scale: scale, marbledIndex: 1, marble: marble)
    // Gilt diamond below the books
    let cx: CGFloat = 180, cy: CGFloat = 96, r: CGFloat = 7
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx, y: cy + r))
    ctx.addLine(to: CGPoint(x: cx + r, y: cy))
    ctx.addLine(to: CGPoint(x: cx, y: cy - r))
    ctx.addLine(to: CGPoint(x: cx - r, y: cy))
    ctx.closePath()
    ctx.setFillColor(rgbColor(forestMarble.gilt, 0.9))
    ctx.fillPath()
    save(ctx.makeImage()!, path)
}

// MARK: - Main

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assets = repoRoot.appendingPathComponent("Library/Assets.xcassets")
let iconset = assets.appendingPathComponent("AppIcon.appiconset")
let motifset = assets.appendingPathComponent("LaunchMotif.imageset")

iconLight(iconset.appendingPathComponent("AppIcon.png").path)
iconDark(iconset.appendingPathComponent("AppIcon-dark.png").path)
iconTinted(iconset.appendingPathComponent("AppIcon-tinted.png").path)
launchMotif(motifset.appendingPathComponent("launch-motif.png").path)
print("done")

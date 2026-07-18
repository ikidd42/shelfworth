import UIKit

/// Procedural 19th-century marbled paper, rendered on demand and cached.
///
/// Uses classical "mathematical marbling": a sheet is built from a sequence
/// of ink drops and comb (tine) strokes, and each output pixel is resolved
/// by inverting that sequence — the standard constant-memory method after
/// Aubrey Jaffer's ink-marbling formulas. Three period patterns:
///
/// - `stone`:     crowded ink drops pushed into crescents, with gilt veins
/// - `nonpareil`: continuous color bands pulled through a fine comb (chevrons)
/// - `bouquet`:   nonpareil followed by a wide reverse comb (flame arches)
///
/// Rendering is deterministic per (kind, pattern, seed), so a given book
/// always gets the same sheet.
enum Marbling {

    nonisolated enum Kind: String, CaseIterable {
        /// Oxblood / ochre / cream with slate accents and gold veins.
        case crimson
        /// Indigo / steel / cream with oxblood accents.
        case indigo
        /// Forest green / sage / cream with russet accents.
        case forest

        var base: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.93, 0.89, 0.78)
            case .indigo: return (0.90, 0.89, 0.82)
            case .forest: return (0.91, 0.90, 0.79)
            }
        }
        var mid: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.76, 0.52, 0.28)
            case .indigo: return (0.42, 0.50, 0.64)
            case .forest: return (0.47, 0.59, 0.45)
            }
        }
        var vein: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.47, 0.19, 0.14)
            case .indigo: return (0.13, 0.19, 0.33)
            case .forest: return (0.11, 0.25, 0.18)
            }
        }
        /// Fourth ink for sparks of contrast, used sparingly in the cycles.
        var accent: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.30, 0.33, 0.42)
            case .indigo: return (0.47, 0.19, 0.14)
            case .forest: return (0.55, 0.42, 0.20)
            }
        }
        var gilt: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.86, 0.69, 0.38)
            case .indigo: return (0.80, 0.72, 0.50)
            case .forest: return (0.83, 0.72, 0.42)
            }
        }

        /// Drop/band ink order: vein (darkest), mid, paper, accent.
        var inks: [(Double, Double, Double)] { [vein, mid, base, accent] }
    }

    nonisolated enum Pattern: String, CaseIterable {
        case stone
        case nonpareil
        case bouquet
    }

    /// Stable djb2 seed — same input always renders the same sheet.
    nonisolated static func stableSeed(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }

    /// About two in five titles get a marbled binding (a real shelf mixes
    /// plain cloth and half-leather volumes, leather-look spines recurring
    /// often enough to read as a collector's shelf rather than a rarity).
    nonisolated static func kind(forTitle title: String) -> Kind? {
        let seed = stableSeed(title)
        guard seed % 5 < 2 else { return nil }
        let kinds = Kind.allCases
        return kinds[Int((seed / 5) % UInt64(kinds.count))]
    }

    /// Board pattern for a book's cover: stone-heavy, with some chevron
    /// nonpareil for shelf variety. Bouquet is reserved for endpapers.
    nonisolated static func boardPattern(forTitle title: String) -> Pattern {
        (stableSeed(title) / 11) % 5 < 3 ? .stone : .nonpareil
    }

    // MARK: - Rendering

    /// NSCache is thread-safe; safe to touch from any isolation domain.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// Returns a cached marbled image, rendering off the main thread on first
    /// use. `size` is in points; the bitmap is rendered at 2×, capped.
    nonisolated static func image(kind: Kind, pattern: Pattern = .stone,
                                  seed: UInt64, size: CGSize) async -> UIImage {
        let w = max(8, min(512, Int(size.width * 2)))
        let h = max(8, min(512, Int(size.height * 2)))
        let key = "\(kind.rawValue)-\(pattern.rawValue)-\(seed)-\(w)x\(h)" as NSString

        if let hit = cache.object(forKey: key) { return hit }

        // Sheet coordinates are tied to point size so pattern scale stays
        // consistent across surfaces: ~2.2 units per point puts 7–10 comb
        // columns across a shelf-size cover.
        let sheetW = size.width * 2.2
        let sheetH = size.height * 2.2

        let rendered = await Task.detached(priority: .userInitiated) {
            render(kind: kind, pattern: pattern, seed: seed,
                   width: w, height: h, sheetW: sheetW, sheetH: sheetH)
        }.value

        cache.setObject(rendered, forKey: key)
        return rendered
    }

    // MARK: - Deterministic RNG (SplitMix64)

    nonisolated private struct SplitMix {
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

    // MARK: - Marbling operations

    nonisolated private enum Op {
        /// An ink drop: displaces the existing pattern radially outward.
        case drop(cx: Double, cy: Double, r: Double, ink: Int)
        /// A periodic comb of parallel tines (columns when `vertical`),
        /// pulling the pattern by `z` with falloff `lambda`.
        case comb(vertical: Bool, spacing: Double, phase: Double,
                  z: Double, lambda: Double, dir: Double)
    }

    /// Inverse-transform a point through one op; returns an ink index when
    /// the point terminates inside a drop.
    nonisolated private static func invert(_ p: inout (x: Double, y: Double), _ op: Op) -> Int? {
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
        case let .comb(vertical, s, phase, z, lambda, dir):
            let coord = vertical ? p.x : p.y
            let t = (coord - phase) / s
            let frac = t - t.rounded(.down)
            let d = abs(frac - 0.5) * s        // distance from tine midline
            let dTine = s / 2 - d              // distance to nearest tine
            let u = dir * z * lambda / (dTine + lambda)
            if vertical { p.y -= u } else { p.x -= u }
            return nil
        }
    }

    // MARK: - Pattern recipes

    nonisolated private static func stoneOps(rng: inout SplitMix, w: Double, h: Double) -> [Op] {
        var ops: [Op] = []
        // Crowd the sheet: hundreds of overlapping drops so later stones push
        // earlier ones into crescents and almost no bare paper survives.
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

    nonisolated private static func combOps(rng: inout SplitMix, pattern: Pattern) -> [Op] {
        // Combed patterns start from continuous horizontal color bands (the
        // raked sheet); a fine downward comb makes nonpareil chevrons.
        var ops: [Op] = [
            .comb(vertical: true, spacing: 34, phase: rng.range(0, 34),
                  z: 240, lambda: 22, dir: 1)
        ]
        if pattern == .bouquet {
            // Wide upward comb over the fine one → flame arches
            ops.append(.comb(vertical: true, spacing: 102, phase: rng.range(0, 102),
                             z: 210, lambda: 44, dir: -1))
        }
        return ops
    }

    // MARK: - Noise

    nonisolated private static func lattice(_ ix: Int, _ iy: Int, _ seed: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64(ix)) &* 0x9E3779B97F4A7C15
        h &+= UInt64(bitPattern: Int64(iy)) &* 0xC2B2AE3D27D4EB4F
        h ^= seed
        h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
        return Double((h ^ (h >> 31)) >> 11) / Double(1 << 53)
    }

    nonisolated private static func smootherstep(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    nonisolated private static func valueNoise(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
        let ix = Int(x.rounded(.down)), iy = Int(y.rounded(.down))
        let fx = smootherstep(x - Double(ix)), fy = smootherstep(y - Double(iy))
        let a = lattice(ix, iy, seed), b = lattice(ix + 1, iy, seed)
        let c = lattice(ix, iy + 1, seed), d = lattice(ix + 1, iy + 1, seed)
        let ab = a + (b - a) * fx, cd = c + (d - c) * fx
        return ab + (cd - ab) * fy
    }

    nonisolated private static func fbm(_ x: Double, _ y: Double, _ octaves: Int, _ seed: UInt64) -> Double {
        var v = 0.0, amp = 0.5, freq = 1.0
        for i in 0..<octaves {
            v += amp * valueNoise(x * freq, y * freq, seed &+ UInt64(i) &* 0x85EBCA6B)
            amp *= 0.5
            freq *= 2
        }
        return v
    }

    nonisolated private static func mix(_ a: (Double, Double, Double),
                                        _ b: (Double, Double, Double),
                                        _ t: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    // MARK: - Render

    nonisolated private static func render(kind: Kind, pattern: Pattern, seed: UInt64,
                                           width w: Int, height h: Int,
                                           sheetW: Double, sheetH: Double) -> UIImage {
        var rng = SplitMix(seed: seed)
        let ops: [Op]
        switch pattern {
        case .stone: ops = stoneOps(rng: &rng, w: sheetW, h: sheetH)
        case .nonpareil, .bouquet: ops = combOps(rng: &rng, pattern: pattern)
        }
        let reversedOps = Array(ops.reversed())
        let banded = pattern != .stone
        let inks = kind.inks
        let paper = kind.base
        let gilt = kind.gilt
        let unitsPerPixelX = sheetW / Double(w)
        let unitsPerPixelY = sheetH / Double(h)
        // Stone gets a stronger hand-made wobble; combed patterns stay crisp.
        let wobble = banded ? 2.2 : 6.0

        // Rows write disjoint pixel ranges, so sharing the raw buffer across
        // concurrentPerform workers is safe; the wrapper states that intent.
        struct RawPixels: @unchecked Sendable {
            let out: UnsafeMutablePointer<UInt8>
        }

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let raw = RawPixels(out: buffer.baseAddress!)
            // Pure per-pixel work parallelizes trivially across rows.
            DispatchQueue.concurrentPerform(iterations: h) { py in
                let out = raw.out
                for px in 0..<w {
                    var p = (x: Double(px) * unitsPerPixelX, y: Double(py) * unitsPerPixelY)
                    // Gentle wobble so nothing is geometrically perfect
                    p.x += (fbm(p.y * 0.012, p.x * 0.012, 3, seed &+ 3) - 0.5) * 2 * wobble
                    p.y += (fbm(p.x * 0.011 + 9.7, p.y * 0.011, 3, seed &+ 5) - 0.5) * 2 * wobble

                    var ink: Int? = nil
                    for op in reversedOps {
                        if let hit = invert(&p, op) { ink = hit; break }
                    }

                    var c: (Double, Double, Double)
                    if let ink {
                        c = inks[ink]
                    } else if banded {
                        // Continuous pre-comb bands, breathing slightly in width
                        let bandH = 34.0
                        let breathe = (valueNoise(p.y * 0.02, 3.7, seed &+ 21) - 0.5) * 8
                        let idx = Int(((p.y + breathe) / bandH).rounded(.down))
                        let cycle = [0, 1, 2, 3, 2, 1]
                        c = inks[cycle[((idx % cycle.count) + cycle.count) % cycle.count]]
                    } else {
                        c = paper
                    }

                    if pattern == .stone {
                        // Smooth ridged-fbm vein network in gilt (Stormont-style)
                        let vx = Double(px) * 0.016, vy = Double(py) * 0.016
                        let ridge = 1 - abs(2 * fbm(vx, vy, 4, seed &+ 11) - 1)
                        if ridge > 0.965 {
                            let strength = (ridge - 0.965) / 0.035
                            c = mix(c, gilt, 0.55 + 0.35 * strength)
                        }
                    }

                    // Paper grain
                    let grain = 0.965 + 0.07 * lattice(px, py, seed &+ 7)
                    let i = (py * w + px) * 4
                    out[i] = UInt8(clamping: Int(c.0 * grain * 255))
                    out[i + 1] = UInt8(clamping: Int(c.1 * grain * 255))
                    out[i + 2] = UInt8(clamping: Int(c.2 * grain * 255))
                    out[i + 3] = 255
                }
            }
        }

        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let cgImage = CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }
}

import UIKit

/// Procedural 19th-century marbled paper, rendered on demand and cached.
///
/// The pattern is a classic combed "nonpareil": fine wavy stripes domain-
/// warped by two octaves of value noise, then mapped through a three-tone
/// palette with gilt veins near the ridge peaks. Rendering is deterministic
/// per seed, so a given book always gets the same sheet.
enum Marbling {

    nonisolated enum Kind: String, CaseIterable {
        /// Deep red / ochre / cream with gold veins.
        case crimson
        /// Indigo / steel / cream.
        case indigo
        /// Forest green / sage / cream.
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
            case .crimson: return (0.74, 0.47, 0.22)
            case .indigo: return (0.42, 0.50, 0.64)
            case .forest: return (0.47, 0.59, 0.45)
            }
        }
        var vein: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.40, 0.13, 0.10)
            case .indigo: return (0.13, 0.19, 0.33)
            case .forest: return (0.11, 0.25, 0.18)
            }
        }
        var gilt: (Double, Double, Double) {
            switch self {
            case .crimson: return (0.86, 0.69, 0.38)
            case .indigo: return (0.80, 0.72, 0.50)
            case .forest: return (0.83, 0.72, 0.42)
            }
        }
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

    // MARK: - Rendering

    /// NSCache is thread-safe; safe to touch from any isolation domain.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// Returns a cached marbled image, rendering off the main thread on first
    /// use. `size` is in points; the bitmap is rendered at 2×, capped.
    nonisolated static func image(kind: Kind, seed: UInt64, size: CGSize) async -> UIImage {
        let w = max(8, min(512, Int(size.width * 2)))
        let h = max(8, min(512, Int(size.height * 2)))
        let key = "\(kind.rawValue)-\(seed)-\(w)x\(h)" as NSString

        if let hit = cache.object(forKey: key) { return hit }

        let rendered = await Task.detached(priority: .userInitiated) {
            render(kind: kind, seed: seed, width: w, height: h)
        }.value

        cache.setObject(rendered, forKey: key)
        return rendered
    }

    // MARK: - Noise

    nonisolated private static func lattice(_ ix: Int, _ iy: Int, _ seed: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64(ix)) &* 0x9E3779B97F4A7C15
        h &+= UInt64(bitPattern: Int64(iy)) &* 0xC2B2AE3D27D4EB4F
        h ^= seed
        h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
        h = h ^ (h >> 31)
        return Double(h >> 11) / Double(1 << 53)
    }

    nonisolated private static func smootherstep(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    nonisolated private static func valueNoise(x: Double, y: Double, seed: UInt64) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = smootherstep(x - Double(ix))
        let fy = smootherstep(y - Double(iy))

        let a = lattice(ix, iy, seed)
        let b = lattice(ix + 1, iy, seed)
        let c = lattice(ix, iy + 1, seed)
        let d = lattice(ix + 1, iy + 1, seed)

        let ab = a + (b - a) * fx
        let cd = c + (d - c) * fx
        return ab + (cd - ab) * fy
    }

    nonisolated private static func fbm(x: Double, y: Double, octaves: Int, seed: UInt64) -> Double {
        var value = 0.0, amplitude = 0.5, frequency = 1.0
        for i in 0..<octaves {
            value += amplitude * valueNoise(x: x * frequency, y: y * frequency,
                                            seed: seed &+ UInt64(i) &* 0x85EBCA6B)
            amplitude *= 0.5
            frequency *= 2.0
        }
        return value
    }

    // MARK: - Combed marble

    nonisolated private static func render(kind: Kind, seed: UInt64, width w: Int, height h: Int) -> UIImage {
        var pixels = [UInt8](repeating: 255, count: w * h * 4)

        // Stripe density scales with the sheet; ~7px per ridge gives the
        // fine, visibly undulating combing of nonpareil marbling.
        let periods = Double(h) / 7.0
        let freq = periods * 2 * .pi / 6.0
        let scale = 6.0 / Double(max(w, h))

        for py in 0..<h {
            let y = Double(py) * scale
            for px in 0..<w {
                let x = Double(px) * scale

                // Domain warp: two noise fields comb the stripes into waves.
                let warp1 = fbm(x: x * 2.2, y: y * 2.2, octaves: 4, seed: seed)
                let warp2 = fbm(x: x * 2.2 + 5.2, y: y * 2.2 + 1.3, octaves: 3, seed: seed ^ 0x9E3779B9)

                let t = 0.5 + 0.5 * sin(y * freq + x * 0.3 + warp1 * 12.0 + warp2 * 4.0)
                let ridge = pow(t, 0.65)

                // Three-tone blend with gilt veins at the ridge peaks.
                var c = mix(kind.base, kind.mid, smoothstep(0.50, 0.74, ridge))
                c = mix(c, kind.vein, smoothstep(0.76, 0.92, ridge))
                let gold = smoothstep(0.955, 0.99, ridge) * 0.85
                c = mix(c, kind.gilt, gold)

                // Paper grain
                let grain = 0.965 + 0.07 * lattice(px, py, seed &+ 7)
                let i = (py * w + px) * 4
                pixels[i] = UInt8(clamping: Int(c.0 * grain * 255))
                pixels[i + 1] = UInt8(clamping: Int(c.1 * grain * 255))
                pixels[i + 2] = UInt8(clamping: Int(c.2 * grain * 255))
                pixels[i + 3] = 255
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

    nonisolated private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    nonisolated private static func mix(_ c1: (Double, Double, Double),
                            _ c2: (Double, Double, Double),
                            _ t: Double) -> (Double, Double, Double) {
        (c1.0 + (c2.0 - c1.0) * t,
         c1.1 + (c2.1 - c1.1) * t,
         c1.2 + (c2.2 - c1.2) * t)
    }
}

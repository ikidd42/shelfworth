import Testing
import UIKit
@testable import Library

struct MarblingTests {

    // MARK: - Seeding

    @Test func stableSeedIsDeterministic() {
        #expect(Marbling.stableSeed("The Hobbit") == Marbling.stableSeed("The Hobbit"))
        #expect(Marbling.stableSeed("") == 5381) // djb2 initial value
    }

    @Test func differentTitlesGetDifferentSeeds() {
        #expect(Marbling.stableSeed("Dune") != Marbling.stableSeed("Emma"))
    }

    // MARK: - Binding assignment

    @Test func kindIsStablePerTitle() {
        for title in ["Dune", "The Hobbit", "Emma", "1984"] {
            #expect(Marbling.kind(forTitle: title) == Marbling.kind(forTitle: title))
        }
    }

    @Test func allColorwaysAppearAcrossACorpus() {
        let kinds = Set((0..<250).map { Marbling.kind(forTitle: "Volume \($0)") })
        #expect(kinds == Set(Marbling.Kind.allCases))
    }

    // MARK: - Rendering

    @Test func rendersAtTwiceThePointSizeCappedAt512() async {
        let small = await Marbling.image(kind: .forest, seed: 1, size: CGSize(width: 50, height: 60))
        #expect(small.size == CGSize(width: 100, height: 120))

        let large = await Marbling.image(kind: .forest, seed: 2, size: CGSize(width: 600, height: 600))
        #expect(large.size == CGSize(width: 512, height: 512))
    }

    @Test func repeatRequestsHitTheCache() async {
        let first = await Marbling.image(kind: .indigo, seed: 7, size: CGSize(width: 40, height: 40))
        let second = await Marbling.image(kind: .indigo, seed: 7, size: CGSize(width: 40, height: 40))
        #expect(first === second)
    }

    // MARK: - Patterns

    @Test func boardPatternIsStableAndBoardOnly() {
        for title in ["Dune", "The Hobbit", "Emma", "1984"] {
            let pattern = Marbling.boardPattern(forTitle: title)
            #expect(pattern == Marbling.boardPattern(forTitle: title))
            #expect(pattern != .bouquet) // bouquet is reserved for endpapers
        }
    }

    @Test func boardPatternMixesStoneAndNonpareil() {
        let patterns = Set((0..<200).map { Marbling.boardPattern(forTitle: "Volume \($0)") })
        #expect(patterns == [.stone, .nonpareil])
    }

    @Test func patternsAreCachedSeparately() async {
        let stone = await Marbling.image(kind: .forest, pattern: .stone, seed: 3,
                                         size: CGSize(width: 40, height: 40))
        let bouquet = await Marbling.image(kind: .forest, pattern: .bouquet, seed: 3,
                                           size: CGSize(width: 40, height: 40))
        #expect(stone !== bouquet)
    }

    @Test func patternsProduceDifferentSheets() async {
        let size = CGSize(width: 30, height: 30)
        let stone = await Marbling.image(kind: .crimson, pattern: .stone, seed: 5, size: size)
        let nonpareil = await Marbling.image(kind: .crimson, pattern: .nonpareil, seed: 5, size: size)
        #expect(stone.pngData() != nonpareil.pngData())
    }

    // MARK: - Cover-matched palettes

    @MainActor
    private func syntheticCover(_ top: UIColor, _ bottom: UIColor) -> Data {
        let size = CGSize(width: 120, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            top.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
            bottom.setFill()
            ctx.fill(CGRect(x: 0, y: 90, width: 120, height: 90))
        }
        return image.pngData()!
    }

    @MainActor
    @Test func extractsDominantInksFromCoverArt() throws {
        let data = syntheticCover(
            UIColor(red: 0.1, green: 0.3, blue: 0.5, alpha: 1),   // dark blue
            UIColor(red: 0.9, green: 0.8, blue: 0.6, alpha: 1)    // cream
        )
        let palette = try #require(Marbling.palette(matchingCover: data))

        // Darkest ink should land near the dark blue (blue-dominant, dark)
        let vein = palette.inks[0]
        #expect(vein.2 > vein.0, "vein should stay blue-dominant, got \(vein)")
        #expect(vein.0 + vein.1 + vein.2 < 1.6, "vein should be dark, got \(vein)")
    }

    @MainActor
    @Test func matchedPaletteIsDeterministic() throws {
        let data = syntheticCover(.systemIndigo, .systemOrange)
        let first = try #require(Marbling.palette(matchingCover: data))
        let second = try #require(Marbling.palette(matchingCover: data))
        #expect(first.fingerprint == second.fingerprint)
    }

    @Test func rejectsUndecodableCoverData() {
        #expect(Marbling.palette(matchingCover: Data([0x00, 0x01, 0x02])) == nil)
    }
}

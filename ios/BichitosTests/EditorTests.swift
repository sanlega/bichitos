import XCTest
@testable import Bichitos

final class EditorTests: XCTestCase {
    func testEveryChipPicksOnlyItsGene() {
        var rng = SeededRNG(seed: 3)
        let base = Recipe.random(using: &rng)
        for gene in Gene.allCases {
            for i in 0..<gene.count {
                var r = base
                r.choose(i, gene)
                XCTAssertEqual(r.choice(gene), i, "\(gene) \(i)")
                XCTAssertFalse(gene.label(i).isEmpty)
                for other in Gene.allCases where other != gene {
                    XCTAssertEqual(r.choice(other), base.choice(other), "\(gene) \(i) changed \(other)")
                }
                XCTAssertEqual(r.seed, base.seed)
                XCTAssertEqual(r.roundness, base.roundness)
                XCTAssertEqual(r.legLength, base.legLength)
            }
        }
    }

    func testRowsCoverEveryOption() {
        XCTAssertEqual(Gene.body.count, 6)
        XCTAssertEqual(Gene.eyes.count, 5)
        XCTAssertEqual(Gene.legs.count, 4)
        XCTAssertEqual(Gene.palette.count, Palette.all.count)
        XCTAssertEqual(Gene.personality.count, 6)
        XCTAssertEqual(Gene.legs.label(0), "sin patas")
        XCTAssertEqual(Gene.personality.label(5), "romántica")
    }

    func testFineTunesWriteTheirGene() {
        var rng = SeededRNG(seed: 4)
        var r = Recipe.random(using: &rng)
        for tune in Gene.allCases.flatMap(\.fineTunes) { r[keyPath: tune.key] = 0.25 }
        XCTAssertEqual([r.roundness, r.height, r.bumps, r.eyeSize, r.eyeSpacing, r.legLength], Array(repeating: 0.25, count: 6))
    }

    func testTypedNameKeepsTheQuirks() {
        let generated = Names.make(seed: 5, language: .es)
        let typed = Names.make(seed: 5, language: .es, name: "Zorro")
        XCTAssertEqual(typed.name, "Zorro")
        XCTAssertTrue(typed.description.hasPrefix("Zorro, "))
        XCTAssertEqual(typed.description.dropFirst(5), generated.description.dropFirst(generated.name.count))
    }
}

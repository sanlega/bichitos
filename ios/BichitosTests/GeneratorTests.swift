import XCTest
@testable import Bichitos

// Foundation also has an `Expression` type (iOS 18+), so name ours explicitly.
typealias Face = Bichitos.Expression

final class GeneratorTests: XCTestCase {
    static func recipe(_ seed: UInt64) -> Recipe {
        var rng = SeededRNG(seed: seed)
        return .random(using: &rng)
    }

    private func opaque(_ g: PixelGrid) -> [(Int, Int)] {
        (0..<g.height).flatMap { y in (0..<g.width).compactMap { x in g[x, y] == 0 ? nil : (x, y) } }
    }

    func testSameInputsGiveSamePixels() {
        for seed in UInt64(1)...20 {
            let r = Self.recipe(seed)
            XCTAssertEqual(Generator.render(r, expression: .happy, squash: 0.8, legFrame: 1, wellbeing: 0.3),
                           Generator.render(r, expression: .happy, squash: 0.8, legFrame: 1, wellbeing: 0.3))
        }
    }

    func testEveryShapeStaysInsideTheCanvas() {
        var base = Self.recipe(1)
        for body in Recipe.Body.allCases {
            for eyes in Recipe.Eyes.allCases {
                for legs in Recipe.legOptions {
                    for personality in Recipe.Personality.allCases {
                        for t in [0.0, 0.5, 1.0] {
                            base.body = body; base.eyes = eyes; base.legs = legs; base.personality = personality
                            base.roundness = t; base.height = t; base.bumps = t; base.eyeSize = t; base.eyeSpacing = t; base.legLength = t
                            for squash in [0.7, 1.0, 1.3] {
                                let g = Generator.render(base, squash: squash, wellbeing: 1 - t)
                                let px = opaque(g)
                                let name = "\(body) \(eyes) \(legs) \(personality) t=\(t) squash=\(squash)"
                                XCTAssertGreaterThan(px.count, 60, name)
                                XCTAssertFalse(px.contains { $0.0 == 0 || $0.0 == g.width - 1 || $0.1 == 0 }, "touches an edge: \(name)")
                                XCTAssertTrue(px.contains { $0.1 == g.height - 1 }, "not on the ground: \(name)")
                                XCTAssertTrue(px.allSatisfy { g[g.width - 1 - $0.0, $0.1] != 0 }, "not symmetric: \(name)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testSquashKeepsTheArea() {
        for seed in UInt64(1)...100 {
            let r = Self.recipe(seed)
            let area = opaque(Generator.render(r)).count
            for squash in [0.7, 1.3] {
                let squashed = opaque(Generator.render(r, squash: squash)).count
                XCTAssertEqual(Double(squashed), Double(area), accuracy: Double(area) * 0.15, "seed \(seed) squash \(squash)")
            }
        }
    }

    func testEveryExpressionChangesTheFace() {
        for seed in UInt64(1)...30 {
            let r = Self.recipe(seed)
            let normal = Generator.render(r)
            for face in Face.allCases where face != .normal {
                XCTAssertNotEqual(Generator.render(r, expression: face), normal, "seed \(seed) \(face)")
            }
        }
    }

    func testNoOrphanPixels() {
        for seed in UInt64(1)...100 {
            let r = Self.recipe(seed)
            for face in Face.allCases {
                for frame in 0...1 {
                    let g = Generator.render(r, expression: face, squash: [0.7, 1, 1.3][Int(seed % 3)], legFrame: frame)
                    for (x, y) in opaque(g) {
                        let alone = (-1...1).allSatisfy { dy in (-1...1).allSatisfy { dx in (dx == 0 && dy == 0) || g[x + dx, y + dy] == 0 } }
                        XCTAssertFalse(alone, "seed \(seed) \(face) orphan at \(x),\(y)")
                    }
                }
            }
        }
    }

    func testPalettes() {
        XCTAssertEqual(Palette.all.count, Recipe.paletteCount)
        for p in Palette.all {
            XCTAssertEqual(p.colors.count, 8)
            XCTAssertEqual(p.colors[0].a, 0)
            let grey = p.desaturate(1)
            XCTAssertEqual(grey.colors[6], p.colors[6])  // white has no colour to lose
            XCTAssertNotEqual(grey.colors[3], p.colors[3])
            XCTAssertEqual(p.desaturate(0), p)
        }
    }
}

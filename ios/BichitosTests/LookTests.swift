import XCTest
@testable import Bichitos

final class LookTests: XCTestCase {
    private let fed = Bichito.Needs()

    func testMoodPicksTheFace() {
        let cases: [(Bichito.Mood, Face)] = [
            (.wander, .normal), (.sleep, .asleep), (.love, .inLove), (.fight, .angry), (.scared, .scared),
            (.flee, .scared), (.happy, .happy), (.eat, .hungry), (.incubating, .normal),
        ]
        for (mood, face) in cases {
            XCTAssertEqual(Look.expression(mood: mood, needs: fed, dizzy: 0, blinking: false), face, mood.rawValue)
        }
    }

    func testDizzyHungerAndBlinkOverrides() {
        XCTAssertEqual(Look.expression(mood: .sleep, needs: fed, dizzy: 0.5, blinking: false), .dizzy)
        var starving = fed
        starving.hunger = 0.1
        XCTAssertEqual(Look.expression(mood: .wander, needs: starving, dizzy: 0, blinking: true), .hungry)
        XCTAssertEqual(Look.expression(mood: .love, needs: starving, dizzy: 0, blinking: false), .inLove)
        XCTAssertEqual(Look.expression(mood: .wander, needs: fed, dizzy: 0, blinking: true), .blink)
        XCTAssertEqual(Look.expression(mood: .sleep, needs: fed, dizzy: 0, blinking: true), .asleep)
    }

    func testBubbles() {
        XCTAssertNil(Look.bubble(mood: .wander, needs: fed, dizzy: 0))
        XCTAssertEqual(Look.bubble(mood: .sleep, needs: fed, dizzy: 0), .zzz)
        XCTAssertEqual(Look.bubble(mood: .wander, needs: fed, dizzy: 2), .dizzy)
    }

    func testEveryMoodMapsToAnIcon() {
        let cases: [(Bichito.Mood, Look.Icon?)] = [
            (.wander, nil), (.sleep, .zzz), (.eat, .hunger), (.love, .heart), (.fight, .anger), (.chase, nil),
            (.flee, .sweat), (.imitate, nil), (.scared, .alert), (.happy, .note), (.held, nil), (.incubating, .egg),
        ]
        var starving = fed
        starving.hunger = 0.1
        for (mood, icon) in cases {
            XCTAssertEqual(Look.bubble(mood: mood, needs: fed, dizzy: 0), icon, mood.rawValue)
            XCTAssertNotNil(Look.bubble(mood: mood, needs: starving, dizzy: 0), "\(mood.rawValue) hungry")
            XCTAssertEqual(Look.bubble(mood: mood, needs: fed, dizzy: 1), .dizzy, mood.rawValue)
        }
        let used = Set(cases.compactMap(\.1) + [.dizzy, .suitcase])
        XCTAssertEqual(used, Set(Look.Icon.allCases), "every icon is drawn for some state")
    }

    /// 12×12, only palette digits, no lone pixels, and a closed 1 px outline: anything but outline is surrounded.
    func testIconGridsAreValid() {
        let n = Look.Icon.canvas
        for icon in Look.Icon.allCases {
            let art = icon.art, g = icon.grid
            XCTAssertEqual(art.count, n, icon.rawValue)
            for row in art {
                XCTAssertEqual(row.count, n, icon.rawValue)
                XCTAssertTrue(row.allSatisfy { ".12346".contains($0) }, "\(icon.rawValue): \(row)")
            }
            XCTAssertTrue((0..<n).contains { g[$0, n - 1] != 0 }, "\(icon.rawValue) rests on the bottom row")
            for y in 0..<n {
                for x in 0..<n where g[x, y] != 0 {
                    let around = [(1, 0), (-1, 0), (0, 1), (0, -1)].map { g[x + $0.0, y + $0.1] }
                    XCTAssertTrue(around.contains { $0 != 0 }, "\(icon.rawValue): orphan at \(x),\(y)")
                    guard g[x, y] != 1 else { continue }
                    for dy in -1...1 {
                        for dx in -1...1 {
                            XCTAssertTrue(g.contains(x + dx, y + dy) && g[x + dx, y + dy] != 0,
                                          "\(icon.rawValue): unoutlined pixel at \(x),\(y)")
                        }
                    }
                }
            }
        }
    }

    func testIconTexturesAreCrispAndTheHeartTakesTheAccent() {
        let cache = Sprites()
        let a = Palette.all[0].colors[5], b = Palette.all[5].colors[5]
        let zzz = cache.texture(.zzz, accent: a)
        XCTAssertTrue(zzz === cache.texture(.zzz, accent: b), "only the heart depends on the bichito")
        XCTAssertEqual(zzz.filteringMode, .nearest)
        XCTAssertEqual(zzz.size(), CGSize(width: Look.Icon.canvas, height: Look.Icon.canvas), "no shadow row")
        XCTAssertFalse(cache.texture(.heart, accent: a) === cache.texture(.heart, accent: b))
        XCTAssertEqual(Look.Icon.heart.palette(accent: a).colors[3], a)
    }

    func testNoEmojiLeftInLook() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Bichitos/Look.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let emoji = text.unicodeScalars.filter { $0.properties.isEmoji && $0.value > 0x7F }
        XCTAssertTrue(emoji.isEmpty, "emoji in Look.swift: \(String(String.UnicodeScalarView(emoji)))")
    }

    func testQuantisation() {
        XCTAssertEqual(Look.squashLevels[Look.squashLevel(1)], 1)
        XCTAssertEqual(Look.squashLevel(0.1), 0)
        XCTAssertEqual(Look.squashLevel(2), Look.squashLevels.count - 1)
        XCTAssertEqual(Look.squashLevels[Look.squashLevel(0.84)], 0.8, accuracy: 1e-9)
        XCTAssertEqual(Look.wellbeingLevel(fed), Look.wellbeingSteps)
        XCTAssertEqual(Look.wellbeingLevel(Bichito.Needs(hunger: 0, sleep: 0, affection: 0)), 0)
    }

    func testSpringSettlesBackToRest() {
        var s = Spring()
        s.kick(-3)
        var lowest = 1.0
        for _ in 0..<12 { s.step(1 / 60); lowest = min(lowest, s.squash) }
        XCTAssertLessThan(lowest, 0.9, "a kick visibly squashes")
        for _ in 0..<240 { s.step(1 / 60) }
        XCTAssertEqual(s.squash, 1, accuracy: 0.01)
    }

    func testTextureCache() {
        let cache = Sprites()
        let key = SpriteKey(recipe: GeneratorTests.recipe(3), squash: Look.squashLevel(1), expression: .normal, legFrame: 0, wellbeing: 3)
        let a = cache.texture(key)
        XCTAssertTrue(a === cache.texture(key))
        XCTAssertEqual(a.filteringMode, .nearest)
        XCTAssertEqual(a.size(), CGSize(width: Sprites.width, height: Sprites.height))
        var happy = key
        happy.expression = .happy
        XCTAssertFalse(a === cache.texture(happy))
        XCTAssertEqual(cache.count, 2)
    }

    func testShadowRowUnderTheFeet() throws {
        let r = GeneratorTests.recipe(4)
        let grid = Generator.render(r)
        let image = Sprites.image(grid, Palette.of(r))
        XCTAssertEqual(image.height, grid.height + 1)
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let lastRow = data[(grid.height * image.width * 4)...]
        let alphas = stride(from: lastRow.startIndex + 3, to: lastRow.endIndex, by: 4).map { lastRow[$0] }
        XCTAssertTrue(alphas.contains { $0 > 0 && $0 < 255 }, "translucent shadow pixels")
        XCTAssertFalse(alphas.contains(255))
    }

    func testNameAndBubbleAnchorToTheFeetAndTheHead() {
        var grid = PixelGrid(width: 32, height: 32)
        grid[16, 10] = 1 // top of the head: 22 rows above the feet
        grid[16, 31] = 1
        for pixel in [1.0, 3, 5, 8] {
            let at = Look.anchors(grid, pixel: pixel)
            XCTAssertEqual(at.bubble, 22 * pixel + 3, "fixed gap over the head at \(pixel) pt")
            XCTAssertEqual(at.name, -pixel - 2, "fixed gap under the shadow at \(pixel) pt")
        }
        // A real sprite: the bubble sits just over its drawn pixels, well under the top of the canvas.
        let tall = Look.anchors(Generator.render(GeneratorTests.recipe(4)), pixel: 5).bubble
        XCTAssertGreaterThan(tall, 5)
        XCTAssertLessThanOrEqual(tall, 32 * 5 + 3)
    }
}

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
        XCTAssertEqual(Look.bubble(mood: .sleep, needs: fed, dizzy: 0), "💤")
        XCTAssertEqual(Look.bubble(mood: .wander, needs: fed, dizzy: 2), "💫")
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
}

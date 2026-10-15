import XCTest
@testable import Bichitos

final class FoodTests: XCTestCase {
    func testFavoriteIsDeterministicAndCoversAllFive() {
        var a = SeededRNG(seed: 3), b = SeededRNG(seed: 3)
        var seen = Set<Food.Kind>()
        for _ in 0..<100 {
            let x = Recipe.random(using: &a), y = Recipe.random(using: &b)
            XCTAssertEqual(x.favorite, y.favorite)
            seen.insert(x.favorite)
        }
        XCTAssertEqual(seen, Set(Food.Kind.allCases))
    }

    func testChildInheritsOneParentsFavorite() {
        var rng = SeededRNG(seed: 19)
        var foreign = 0, fromA = 0
        for _ in 0..<300 {
            let a = Recipe.random(using: &rng), b = Recipe.random(using: &rng)
            let c = Recipe.child(of: a, and: b, using: &rng)
            XCTAssertNotNil(c.favoriteFood)
            if c.favorite != a.favorite && c.favorite != b.favorite { foreign += 1 }
            if c.favorite == a.favorite && a.favorite != b.favorite { fromA += 1 }
        }
        XCTAssertGreaterThan(foreign, 0) // it mutates now and then...
        XCTAssertLessThan(foreign, 60)   // ...but mostly it is inherited
        XCTAssertGreaterThan(fromA, 50)  // and either parent can pass it on
    }

    func testFavoriteFillsMoreAndGivesAffection() {
        var w = World(seed: 1, date: Date(timeIntervalSince1970: 1_700_000_000))
        var rng = SeededRNG(seed: 5)
        let id = w.add(Recipe.random(using: &rng))
        var b = w.bichito(id)!
        let other = Food.Kind.allCases.first { $0 != b.favorite }!
        b.needs = Bichito.Needs(hunger: 0.2, sleep: 1, affection: 0.5)
        b.eat(other)
        XCTAssertEqual(b.needs.hunger, 0.2 + Food.snack, accuracy: 1e-9)
        XCTAssertEqual(b.needs.affection, 0.5, accuracy: 1e-9)
        b.needs.hunger = 0.2
        b.eat(b.favorite)
        XCTAssertEqual(b.needs.hunger, 1, accuracy: 1e-9)
        XCTAssertEqual(b.needs.affection, 0.5 + Food.favoriteAffection, accuracy: 1e-9)
    }

    func testDroppedFoodKeepsItsKind() {
        var w = World(seed: 2)
        let seta = w.dropFood(at: Vec(100, 100), kind: .seta)
        let plain = w.dropFood(at: Vec(50, 50))
        XCTAssertEqual(w.foods.first { $0.id == seta }?.kind, .seta)
        XCTAssertEqual(w.foods.first { $0.id == plain }?.kind, .fruta)
    }

    func testOldSavesStillLoad() throws {
        let food = try JSONDecoder().decode(Food.self, from: Data(#"{"id":3,"pos":{"x":1,"y":2}}"#.utf8))
        XCTAssertEqual(food, Food(id: 3, pos: Vec(1, 2), kind: .fruta))
        let croqueta = Food(id: 4, pos: .zero, kind: .croqueta)
        XCTAssertEqual(try JSONDecoder().decode(Food.self, from: JSONEncoder().encode(croqueta)), croqueta)

        var rng = SeededRNG(seed: 7)
        var recipe = Recipe.random(using: &rng)
        let old = try JSONEncoder().encode(recipe)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("favoriteFood")) // founders keep the old shape
        let loaded = try JSONDecoder().decode(Recipe.self, from: old)
        XCTAssertNil(loaded.favoriteFood)
        XCTAssertEqual(loaded.favorite, recipe.favorite)

        recipe.favoriteFood = .macarron
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe)).favorite, .macarron)
    }

    func testFoodGridsAreValidPixelArt() {
        for kind in Food.Kind.allCases {
            // Every row drawn fits the canvas, so nothing is cut off silently.
            XCTAssertEqual(kind.art.count, Food.canvas, "\(kind)")
            XCTAssertTrue(kind.art.allSatisfy { $0.count == Food.canvas }, "\(kind)")
            let g = kind.grid, colors = kind.palette.colors.count
            var opaque = 0
            for y in 0..<g.height {
                for x in 0..<g.width where g[x, y] != 0 {
                    opaque += 1
                    XCTAssertLessThan(Int(g[x, y]), colors, "\(kind) bad index at \(x),\(y)")
                    let alone = (-1...1).allSatisfy { dy in (-1...1).allSatisfy { dx in (dx == 0 && dy == 0) || g[x + dx, y + dy] == 0 } }
                    XCTAssertFalse(alone, "\(kind) orphan at \(x),\(y)")
                    // 1 px outline of the darkest tone: whatever touches the outside is index 1.
                    let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { g[x + $0.0, y + $0.1] == 0 }
                    if edge { XCTAssertEqual(g[x, y], 1, "\(kind) not outlined at \(x),\(y)") }
                }
            }
            XCTAssertGreaterThan(opaque, 40, "\(kind)")
            XCTAssertTrue((0..<g.width).contains { g[$0, g.height - 1] != 0 }, "\(kind) rests on the bottom row")
        }
    }

    func testFavoriteHasLocalisedNames() {
        XCTAssertEqual(Food.Kind.macarron.name(.es), "macarrón")
        XCTAssertEqual(Food.Kind.croqueta.name(.en), "croquette")
        var w = World(seed: 4)
        var rng = SeededRNG(seed: 8)
        var r = Recipe.random(using: &rng)
        r.favoriteFood = .croqueta
        let id = w.add(r)
        let b = w.bichito(id)!
        XCTAssertEqual(b.favorite, .croqueta)
        XCTAssertEqual(b.lovesLine(.es), "le encanta: croqueta")
        XCTAssertEqual(b.lovesLine(.en), "loves: croquette")
    }
}

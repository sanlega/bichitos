import XCTest
@testable import Bichitos

final class RecipeTests: XCTestCase {
    func testSameSeedGivesSameRecipe() {
        var a = SeededRNG(seed: 42), b = SeededRNG(seed: 42)
        XCTAssertEqual(Recipe.random(using: &a), Recipe.random(using: &b))
    }

    func testRecipeSurvivesSaving() throws {
        var rng = SeededRNG(seed: 7)
        let recipe = Recipe.random(using: &rng)
        let data = try JSONEncoder().encode(recipe)
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: data), recipe)
        XCTAssertEqual(recipe.engine, Recipe.currentEngine)
    }
}

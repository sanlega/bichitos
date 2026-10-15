import Foundation

extension Recipe {
    static let categoryMutationChance = 0.1
    static let fineMutation = 0.08

    /// Each category comes from one parent, fine-tunes are averaged and nudged, and once in a while a category mutates.
    static func child<G: RandomNumberGenerator>(of a: Recipe, and b: Recipe, using rng: inout G) -> Recipe {
        var c = Recipe(
            body: Bool.random(using: &rng) ? a.body : b.body,
            roundness: blend(a.roundness, b.roundness, &rng),
            height: blend(a.height, b.height, &rng),
            bumps: blend(a.bumps, b.bumps, &rng),
            eyes: Bool.random(using: &rng) ? a.eyes : b.eyes,
            eyeSize: blend(a.eyeSize, b.eyeSize, &rng),
            eyeSpacing: blend(a.eyeSpacing, b.eyeSpacing, &rng),
            legs: Bool.random(using: &rng) ? a.legs : b.legs,
            legLength: blend(a.legLength, b.legLength, &rng),
            palette: Bool.random(using: &rng) ? a.palette : b.palette,
            personality: Bool.random(using: &rng) ? a.personality : b.personality,
            seed: rng.next(),
            engine: currentEngine
        )
        if Double.random(in: 0..<1, using: &rng) < categoryMutationChance {
            switch Int.random(in: 0..<5, using: &rng) {
            case 0: c.body = Body.allCases.randomElement(using: &rng)!
            case 1: c.eyes = Eyes.allCases.randomElement(using: &rng)!
            case 2: c.legs = legOptions.randomElement(using: &rng)!
            case 3: c.palette = Int.random(in: 0..<paletteCount, using: &rng)
            default: c.personality = Personality.allCases.randomElement(using: &rng)!
            }
        }
        c.favoriteFood = inheritFavorite(a, b, using: &rng)
        return c
    }

    private static func blend<G: RandomNumberGenerator>(_ x: Double, _ y: Double, _ rng: inout G) -> Double {
        min(1, max(0, (x + y) / 2 + Double.random(in: -fineMutation...fineMutation, using: &rng)))
    }
}

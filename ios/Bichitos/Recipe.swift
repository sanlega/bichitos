import Foundation

/// Everything that defines a bichito. Only this is saved; pixels, behaviour and voice are derived from it.
struct Recipe: Codable, Hashable {
    enum Body: String, Codable, CaseIterable { case gota, alubia, torre, cuadradito, pera, estrella }
    enum Eyes: String, Codable, CaseIterable { case normales, saltones, ciclope, tres, adormilados }
    enum Personality: String, Codable, CaseIterable { case curiosa, nerviosa, dormilona, hiperactiva, territorial, romantica }

    var body: Body
    var roundness: Double  // 0...1, fine-tune
    var height: Double     // 0...1, fine-tune
    var bumps: Double      // 0...1, fine-tune
    var eyes: Eyes
    var eyeSize: Double    // 0...1, fine-tune
    var eyeSpacing: Double // 0...1, fine-tune
    var legs: Int          // 0, 2, 4 or 6
    var legLength: Double  // 0...1, fine-tune
    var palette: Int       // index into the palette list (DESIGN.md: 12 palettes)
    var personality: Personality
    var seed: UInt64
    /// Which generator draws this recipe. Old generators are kept so a bichito never changes its face.
    var engine: Int

    static let legOptions = [0, 2, 4, 6]
    static let paletteCount = 12
    static let currentEngine = 1

    static func random<G: RandomNumberGenerator>(using rng: inout G) -> Recipe {
        Recipe(
            body: Body.allCases.randomElement(using: &rng)!,
            roundness: .random(in: 0...1, using: &rng),
            height: .random(in: 0...1, using: &rng),
            bumps: .random(in: 0...1, using: &rng),
            eyes: Eyes.allCases.randomElement(using: &rng)!,
            eyeSize: .random(in: 0...1, using: &rng),
            eyeSpacing: .random(in: 0...1, using: &rng),
            legs: legOptions.randomElement(using: &rng)!,
            legLength: .random(in: 0...1, using: &rng),
            palette: .random(in: 0..<paletteCount, using: &rng),
            personality: Personality.allCases.randomElement(using: &rng)!,
            seed: rng.next(),
            engine: currentEngine
        )
    }
}

/// Deterministic RNG (SplitMix64): the same seed always gives the same pixels and the same simulation.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

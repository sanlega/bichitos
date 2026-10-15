import Foundation

extension Food {
    /// The five foods. Each bichito has a favourite: it fills more and also gives affection.
    enum Kind: String, Codable, CaseIterable {
        case fruta, galleta, seta, croqueta, macarron

        func name(_ language: Language) -> String {
            switch (self, language) {
            case (.fruta, .es): return "fruta"
            case (.fruta, .en): return "fruit"
            case (.galleta, .es): return "galleta"
            case (.galleta, .en): return "cookie"
            case (.seta, .es): return "seta"
            case (.seta, .en): return "mushroom"
            case (.croqueta, .es): return "croqueta"
            case (.croqueta, .en): return "croquette"
            case (.macarron, .es): return "macarrón"
            case (.macarron, .en): return "macaroni"
            }
        }
    }

    static let snack = 0.5             // hunger filled by any food that isn't the favourite
    static let favoriteAffection = 0.2 // affection the favourite gives on top of filling it up
    static let favoriteMutationChance = 0.1

    private enum Keys: String, CodingKey { case id, pos, kind }

    /// Saves from before the five foods have no `kind`: those were all fruit.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decode(Int.self, forKey: .id), pos: try c.decode(Vec.self, forKey: .pos),
                  kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .fruta)
    }
}

extension Recipe {
    /// Founders (and old saves) have no stored gene: it comes from the seed. Children get one from `Recipe.child`.
    var favorite: Food.Kind { favoriteFood ?? Food.Kind.allCases[Int(seed % UInt64(Food.Kind.allCases.count))] }

    /// One parent's favourite, now and then a random one.
    static func inheritFavorite<G: RandomNumberGenerator>(_ a: Recipe, _ b: Recipe, using rng: inout G) -> Food.Kind {
        let f = Bool.random(using: &rng) ? a.favorite : b.favorite
        return Double.random(in: 0..<1, using: &rng) < Food.favoriteMutationChance ? Food.Kind.allCases.randomElement(using: &rng)! : f
    }
}

extension Bichito {
    var favorite: Food.Kind { recipe.favorite }

    /// «le encanta: croqueta» / "loves: croquette", for the ficha.
    func lovesLine(_ language: Language) -> String {
        (language == .es ? "le encanta: " : "loves: ") + favorite.name(language)
    }

    mutating func eat(_ kind: Food.Kind) {
        if kind == favorite {
            needs.hunger = 1
            needs.affection = min(1, needs.affection + Food.favoriteAffection)
        } else {
            needs.hunger = min(1, needs.hunger + Food.snack)
        }
    }
}

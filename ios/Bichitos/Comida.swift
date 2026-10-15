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

    static let canvas = 12

    static let snack = 0.5            // hunger filled by any food that isn't the favourite
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

/// The foods in pixel art (DESIGN.md "Los dos mundos"): hand-drawn 12×12 indexed grids, resting on the bottom row.
extension Food.Kind {
    /// One string per row: '.' transparent, digits are `Palette` indices (1 outline, 2 shadow, 3 base, 4 highlight, 5 accent, 6 white).
    var art: [String] {
        switch self {
        case .fruta: return [
            ".....1.111..", ".....115551.", "..11111111..", ".1443333331.", "144333333321", "143333333321",
            "133333333321", "133333333321", "133333333221", ".1333333221.", "..13332221..", "...111111...",
        ]
        case .galleta: return [
            "...111111...", ".1144433311.", ".1443353331.", "144553333531", "143353333331", "133333355331",
            "135533333321", "133333533221", ".1333332221.", ".1253322221.", "..11222211..", "....1111....",
        ]
        case .seta: return [
            "....1111....", "..11466311..", ".1443333661.", "144663333331", "133663333661", "122222222221",
            ".1111665111.", "....16651...", "....16651...", "....16651...", "....16551...", "....11111...",
        ]
        case .croqueta: return [
            "............", "............", "............", "............", "..11111111..", ".1444445331.",
            "144353333531", "133333533331", "135333333321", "133335332221", ".1222222221.", "..11111111..",
        ]
        case .macarron: return [
            "............", "....11111111", "...144443351", "..1443333251", ".14333221111", ".1433211....",
            "1433321.....", "1433321.....", "1433321.....", "1433321.....", "1333221.....", ".11111......",
        ]
        }
    }

    var grid: PixelGrid {
        var g = PixelGrid(width: Food.canvas, height: Food.canvas)
        for (y, row) in art.enumerated() {
            for (x, c) in row.enumerated() { g[x, y] = UInt8(c.wholeNumberValue ?? 0) }
        }
        return g
    }

    /// Outline, shadow, base, highlight, accent; saturated like the bichitos.
    var palette: Palette {
        switch self {
        case .fruta: return Palette("fruta", [0x6B1E2E, 0xC93B54, 0xF2607A, 0xFFA3B1, 0x7ED957])
        case .galleta: return Palette("galleta", [0x5C3A1A, 0xC48A3F, 0xE8B66A, 0xF7DCA0, 0x6B3E22])
        case .seta: return Palette("seta", [0x5E1A1E, 0xB8323A, 0xE5483F, 0xFF8A70, 0xF2E2C4])
        case .croqueta: return Palette("croqueta", [0x5A3214, 0xB8702E, 0xE09A48, 0xF6C77A, 0x8A4E20])
        case .macarron: return Palette("macarrón", [0x6B5A10, 0xD4B12A, 0xF9DC4A, 0xFFF3A3, 0x8F7414])
        }
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

import Foundation

/// Districts sit side by side, left to right, in unlock order. Only `index` is saved; the rest comes from `themes`.
struct District: Codable, Equatable {
    enum Terrain: String { case sandStar, puddles, rockWalls, meadowHills, circuit, shrubs, flowers }
    enum Monument: String { case fountain, telescope, flagTower, giantHammock, hamsterWheel, hideoutBox, gazebo }

    /// A district's recipe (DESIGN.md, "Barrios").
    struct Theme: Equatable {
        let es: String, en: String
        let tint: UInt32            // 0xRRGGBB
        let terrain: Terrain
        let monument: Monument
        let affine: Recipe.Personality? // nil: home to nobody in particular
    }

    /// Plaza Mayor is always the first one.
    static let themes: [Theme] = [
        Theme(es: "Plaza Mayor", en: "Main Square", tint: 0xF2B48C, terrain: .sandStar, monument: .fountain, affine: nil),
        Theme(es: "Villa Charco", en: "Puddle Town", tint: 0x7FB8C9, terrain: .puddles, monument: .telescope, affine: .curiosa),
        Theme(es: "Las Esquinas", en: "The Corners", tint: 0xC9907F, terrain: .rockWalls, monument: .flagTower, affine: .territorial),
        Theme(es: "Almohadilla", en: "Pillowville", tint: 0xA99BD6, terrain: .meadowHills, monument: .giantHammock, affine: .dormilona),
        Theme(es: "Pista Loca", en: "Crazy Track", tint: 0xE6C55A, terrain: .circuit, monument: .hamsterWheel, affine: .hiperactiva),
        Theme(es: "El Matorral", en: "The Thicket", tint: 0x8DB88A, terrain: .shrubs, monument: .hideoutBox, affine: .nerviosa),
        Theme(es: "La Rosaleda", en: "Rose Garden", tint: 0xE89BB0, terrain: .flowers, monument: .gazebo, affine: .romantica),
    ]

    var index: Int
    var theme: District.Theme { District.themes[index] }
    var rect: Rect { Rect(x: Double(index) * World.districtSize.x, y: 0, w: World.districtSize.x, h: World.districtSize.y) }
    func name(_ language: Language) -> String { language == .es ? theme.es : theme.en }
}

extension World {
    /// Saves from before design v2 can have up to 8 districts. Keeps the first 7 (renamed by index) and
    /// moves everyone who lived further right to the emptiest remaining district, so nobody is lost.
    mutating func fitDistricts() {
        let n = District.themes.count
        guard districts.count > n else { return }
        districts = Array(districts.prefix(n))
        var counts = Array(repeating: 0, count: n)
        for b in bichitos where b.district < n { counts[b.district] += 1 }
        func rehomed(_ b: Bichito) -> Bichito {
            var b = b
            if b.district >= n, let d = counts.indices.min(by: { counts[$0] < counts[$1] }) {
                b.district = d
                counts[d] += 1
            }
            b.pos = clamp(b.pos, b.recipe.radius) // it walks home from the new edge of the map
            return b
        }
        for i in bichitos.indices { bichitos[i] = rehomed(bichitos[i]) }
        for i in notes.indices { notes[i].bichito = rehomed(notes[i].bichito); notes[i].pos = clamp(notes[i].pos, 4) }
        for i in foods.indices { foods[i].pos = clamp(foods[i].pos, 4) }
        for i in eggs.indices { eggs[i].pos = clamp(eggs[i].pos, 8) }
        events.removeAll {
            switch $0 {
            case let .emigrated(_, d), let .unlocked(d): return d >= n
            default: return false
            }
        }
    }
}

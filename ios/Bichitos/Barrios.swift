import Foundation

/// Plaza Mayor in the centre and the six themed districts in a ring around it (`World.layout`).
/// `index` is the theme; a district's place in `World.districts` is its unlock order.
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
    var rect = Rect(x: 0, y: 0, w: 0, h: 0) // empty in saves from before the ring, until `fitDistricts`
    var theme: District.Theme { District.themes[index] }
    func name(_ language: Language) -> String { language == .es ? theme.es : theme.en }
}

extension District {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        rect = try c.decodeIfPresent(Rect.self, forKey: .rect) ?? Rect(x: 0, y: 0, w: 0, h: 0)
    }
}

extension World {
    /// About 12×9 casillas of 32 u (DESIGN.md); 1 u is 2 world units.
    static let districtSize = Vec(768, 576)
    static let districtGap = 128.0 // of bare mist between neighbours

    /// Where each theme's district sits, by theme index: Plaza Mayor at the origin and the six themed ones
    /// shuffled by the seed into the hexagonal ring around it (left, right, and two above and two below, half-offset).
    static func layout(seed: UInt64) -> [Rect] {
        let s = districtSize, px = s.x + districtGap, py = s.y + districtGap
        var slots = [Vec(-px, 0), Vec(px, 0), Vec(-px / 2, -py), Vec(px / 2, -py), Vec(-px / 2, py), Vec(px / 2, py)]
        var rng = SeededRNG(seed: seed)
        slots.shuffle(using: &rng)
        return ([Vec.zero] + slots).map { Rect(x: $0.x, y: $0.y, w: s.x, h: s.y) }
    }

    var layout: [Rect] { World.layout(seed: layoutSeed ?? 0) }

    /// The box around the unlocked districts: the map's walls and the camera's bounds.
    /// A plain loop: it runs for every body on every tick, so no temporary arrays.
    var bounds: Rect {
        guard let first = districts.first?.rect else { return Rect(x: 0, y: 0, w: 0, h: 0) }
        var x0 = first.x, y0 = first.y, x1 = first.x + first.w, y1 = first.y + first.h
        for d in districts {
            x0 = min(x0, d.rect.x); y0 = min(y0, d.rect.y)
            x1 = max(x1, d.rect.x + d.rect.w); y1 = max(y1, d.rect.y + d.rect.h)
        }
        return Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }

    /// Opens the theme's district in its place of the ring.
    mutating func unlock(_ theme: Int) {
        districts.append(District(index: theme, rect: layout[theme]))
    }

    /// The locked district most of the population is affine to; ties go to the earlier theme. `reason` is
    /// that personality, or nil when nobody here is affine to any district still locked (it opens just for room).
    func nextDistrict() -> (theme: Int, reason: Recipe.Personality?)? {
        let taken = Set(districts.map(\.index))
        func fans(_ t: Int) -> Int { bichitos.filter { $0.recipe.personality == District.themes[t].affine }.count }
        guard let t = District.themes.indices.filter({ !taken.contains($0) }).max(by: { fans($0) < fans($1) }) else { return nil }
        return (t, fans(t) > 0 ? District.themes[t].affine : nil)
    }

    /// Saves from before the ring have districts of 1000×1600 in a row, left to right, maybe 8 of them.
    /// Keeps the first 7 (renamed by index), moves whoever lived in the 8th to the emptiest one, and puts
    /// everything at the same spot of its district's new place, so nobody is lost.
    mutating func fitDistricts() {
        guard layoutSeed == nil else { return }
        layoutSeed = rng.state
        let old = Vec(1000, 1600)
        let kept = max(1, min(districts.count, District.themes.count))
        districts = []
        for t in 0..<kept { unlock(t) }
        var counts = Array(repeating: 0, count: kept)
        for b in bichitos where b.district < kept { counts[b.district] += 1 }
        /// Its spot in the old cell under `p`, inside district `d`'s new rect (that cell's when nil), `r` clear of the edge.
        func moved(_ p: Vec, _ d: Int?, _ r: Double) -> Vec {
            let cell = min(max(Int((p.x / old.x).rounded(.down)), 0), kept - 1)
            let to = districts[d ?? cell].rect
            let fx = min(max(p.x / old.x - Double(cell), 0), 1), fy = min(max(p.y / old.y, 0), 1)
            return Vec(to.x + r + fx * (to.w - 2 * r), to.y + r + fy * (to.h - 2 * r))
        }
        func rehomed(_ b: Bichito) -> Bichito {
            var b = b
            if b.district >= kept, let d = counts.indices.min(by: { counts[$0] < counts[$1] }) {
                b.district = d
                counts[d] += 1
            }
            b.pos = moved(b.pos, b.district, b.recipe.radius)
            return b
        }
        for i in bichitos.indices { bichitos[i] = rehomed(bichitos[i]) }
        for i in notes.indices { notes[i].bichito = rehomed(notes[i].bichito); notes[i].pos = moved(notes[i].pos, nil, 4) }
        for i in foods.indices { foods[i].pos = moved(foods[i].pos, nil, 4) }
        for i in eggs.indices { eggs[i].pos = moved(eggs[i].pos, nil, 8) }
        events.removeAll {
            switch $0 {
            case let .emigrated(_, d), let .unlocked(d, _): return d >= kept
            default: return false
            }
        }
    }

    /// One `BarrioPicker` row per district theme. `place` is its position in `districts`, nil while locked.
    /// Open: `population` lives there. Locked: `fans` have its personality (what decides which one opens next).
    struct BarrioRow: Equatable {
        let theme: Int
        let place: Int?
        let population: Int
        let fans: Int
    }

    var barrioRows: [BarrioRow] {
        District.themes.indices.map { t in
            let place = districts.firstIndex { $0.index == t }
            let affine = District.themes[t].affine
            return BarrioRow(theme: t, place: place, population: place.map(population(of:)) ?? 0,
                             fans: place != nil || affine == nil ? 0 : bichitos.filter { $0.recipe.personality == affine }.count)
        }
    }

    /// How many more bichitos open the next district (`unlockIfCrowded`), nil once all are open.
    var bichitosToNextDistrict: Int? {
        districts.count < District.themes.count ? max(1, World.capacity * districts.count + 1 - bichitos.count) : nil
    }

    /// The whole ring, locked districts included: what the Mapa level shows.
    var mapBounds: Rect {
        let rs = layout
        let x0 = rs.map(\.x).min()!, y0 = rs.map(\.y).min()!
        return Rect(x: x0, y: y0, w: rs.map { $0.x + $0.w }.max()! - x0, h: rs.map { $0.y + $0.h }.max()! - y0)
    }

    /// A locked district as the Mapa level draws it: a dashed outline at its place in the ring, with a lock.
    /// `missing` (`bichitosToNextDistrict`) only on the one most likely to open next (`nextDistrict`):
    /// the count is for whichever opens next, so on every lock it would promise them all at once.
    struct LockedOutline: Equatable {
        let theme: Int
        let rect: Rect
        let missing: Int?
    }

    var lockedOutlines: [LockedOutline] {
        let open = Set(districts.map(\.index)), next = nextDistrict()?.theme, missing = bichitosToNextDistrict
        return District.themes.indices.filter { !open.contains($0) }.map {
            LockedOutline(theme: $0, rect: layout[$0], missing: $0 == next ? missing : nil)
        }
    }

    /// Bichitos whose home is `district` (whether or not they are walking there right now).
    func population(of district: Int) -> Int { bichitos.filter { $0.district == district }.count }
}

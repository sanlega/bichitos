import Foundation

/// A building or a piece of decoration (DESIGN.md, "Edificaciones"). Placed by `Terrain` from the layout seed,
/// like the ground, so it is never saved; only `Bichito.home` stores an `id`.
struct Building: Equatable {
    enum Kind: String, CaseIterable {
        case casita, comedero, banco, nido, monument // what the district's theme says for the monument: `District.Theme.monument`
        case tree, bush, rock, flower, fence, lamp   // decoration
        var isDecoration: Bool {
            switch self {
            case .casita, .comedero, .banco, .nido, .monument: return false
            default: return true
            }
        }
    }

    /// Its index in `Terrain.buildings`: the same for the same layout seed, so saves can point at it.
    let id: Int
    let kind: Kind
    /// The district's theme (`District.index`), not its place in `World.districts`.
    let theme: Int
    /// Its box in world units on the 8 u grid, standing on its base (the bottom edge, `y + h`): the size from the catalogue,
    /// drawn front-facing. Fences and low walls are their ground strip, 8 u deep; they are drawn up from it.
    let rect: Rect
    /// The strip of ground it stands on, the bottom of `rect`: what never overlaps another one, nor water, rock or a path.
    /// What is drawn above it may hide what is behind (DESIGN.md, "Perspectiva y unidades").
    let base: Rect
    /// The part that blocks movement, made of whole terrain cells; nil when bichitos walk through it (DESIGN.md).
    let blocks: Rect?
    /// Casitas only: just in front of the door, where its owners sleep.
    let door: Vec?
    /// For the painter's variation (roof, windows, extra; DESIGN.md "Cómo se dibujan").
    let seed: UInt64

    /// Where a bichito sleeps: a casita's door, or beside a tree's trunk, under its crown.
    var bed: Vec? {
        switch kind {
        case .casita: return door
        case .tree: return Vec(rect.x + rect.w / 2 + 28, rect.y + rect.h - 8)
        default: return nil
        }
    }
}

extension Rect {
    func intersects(_ o: Rect) -> Bool { x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h }
}

extension Terrain {
    /// Each district's buildings, then its decoration, from the district's seed. Every one gets room of its own (bases
    /// never overlap, a casita keeps a strip in front of its door) on plain ground: no water, rock or path, clear of the
    /// district's edges. The monument goes in the centre, where the paths end, unless water or rock is there.
    mutating func placeBuildings(seed: UInt64, rects: [Rect]) {
        blocked = [Bool](repeating: false, count: cells.count)
        for (t, rect) in rects.enumerated() {
            var rng = SeededRNG(seed: seed ^ (UInt64(t + 1) &* 0xA24B_AED4_963E_E407))
            let theme = District.themes[t]
            var rooms: [Rect] = []
            var list: [(Building.Kind, Int)] = [(.monument, 1), (.casita, 7), (.comedero, 1), (.banco, 1), (.nido, 1)]
            list += Terrain.decoration(theme.terrain)
            for (kind, n) in list {
                for _ in 0..<n {
                    let size = Terrain.size(kind, &rng)
                    guard let r = findRoom(size, kind, in: rect, avoiding: rooms, &rng) else { continue }
                    rooms.append(Terrain.room(r, kind))
                    add(Building(id: buildings.count, kind: kind, theme: t, rect: r, base: Terrain.base(r, kind), blocks: Terrain.blocks(r, kind),
                                 door: kind == .casita ? Vec(r.x + r.w / 2, r.y + r.h + 20) : nil, seed: rng.next()))
                }
            }
        }
    }

    private mutating func add(_ b: Building) {
        buildings.append(b)
        guard let s = b.blocks else { return }
        for k in cellIndices(s) { blocked[k] = true }
    }

    /// How many of each piece of decoration a district's terrain gets.
    private static func decoration(_ t: District.Terrain) -> [(Building.Kind, Int)] {
        switch t {
        case .sandStar: return [(.tree, 4), (.lamp, 6), (.bush, 2), (.flower, 6)]
        case .puddles: return [(.tree, 4), (.bush, 3), (.rock, 2), (.flower, 4), (.lamp, 2)]
        case .rockWalls: return [(.fence, 6), (.rock, 6), (.tree, 3), (.bush, 2), (.lamp, 2)]
        case .meadowHills: return [(.tree, 7), (.bush, 4), (.flower, 6), (.lamp, 2)]
        case .circuit: return [(.lamp, 6), (.fence, 3), (.tree, 3), (.rock, 2), (.bush, 2)]
        case .shrubs: return [(.bush, 14), (.tree, 4), (.rock, 2), (.lamp, 1)]
        case .flowers: return [(.flower, 20), (.tree, 4), (.bush, 3), (.fence, 2), (.lamp, 2)]
        }
    }

    /// The catalogue size in world units (1 u = 2), on the 8 u grid where it is blocking.
    /// The monument's depth is not in DESIGN.md: 64 u.
    private static func size(_ kind: Building.Kind, _ rng: inout SeededRNG) -> Vec {
        switch kind {
        case .casita: return Vec(96, 96)
        case .comedero: return Vec(80, 48)
        case .banco: return Vec(80, 40)
        case .nido: return Vec(64, 32)
        case .monument: return Vec([192, 224, 256].randomElement(using: &rng)!, 128)
        case .tree: return Vec(80, 112)
        case .bush: return Vec(48, 32)
        case .rock: let s = [32.0, 48, 64].randomElement(using: &rng)!; return Vec(s, s)
        case .flower: return Vec(16, 24)
        case .fence:
            let long = [64.0, 96, 128].randomElement(using: &rng)!
            return Bool.random(using: &rng) ? Vec(long, 16) : Vec(16, long)
        case .lamp: return Vec(16, 80)
        }
    }

    /// The base of casitas and the monument, a tree's trunk (8×8 u), and all of a rock or fence.
    private static func blocks(_ r: Rect, _ kind: Building.Kind) -> Rect? {
        switch kind {
        case .casita: return Rect(x: r.x, y: r.y + r.h - 48, w: r.w, h: 48)
        case .monument: return Rect(x: r.x, y: r.y + r.h - 64, w: r.w, h: 64)
        case .tree: return Rect(x: r.x + r.w / 2 - 8, y: r.y + r.h - 16, w: 16, h: 16)
        case .rock, .fence: return r
        default: return nil
        }
    }

    /// How deep its base is: 24 u for a casita, 32 u for the monument, 16 u under a tree's crown, 8 u under a lamp;
    /// the rest are low enough to stand on all of their rect.
    private static func base(_ r: Rect, _ kind: Building.Kind) -> Rect {
        let depth: Double
        switch kind {
        case .casita: depth = 48
        case .monument: depth = 64
        case .tree: depth = 32
        case .lamp: depth = 16
        default: depth = r.h
        }
        return Rect(x: r.x, y: r.y + r.h - depth, w: r.w, h: depth)
    }

    /// The base and a casita's doorstep: the ground that must be plain.
    private static func ground(_ r: Rect, _ kind: Building.Kind) -> Rect {
        let b = base(r, kind)
        return Rect(x: b.x, y: b.y, w: b.w, h: b.h + (kind == .casita ? 32 : 0))
    }

    /// `ground` plus the gap kept around it, 8 u around buildings and 4 u around decoration: what no other room overlaps.
    private static func room(_ r: Rect, _ kind: Building.Kind) -> Rect {
        let g = ground(r, kind), pad = kind.isDecoration ? 8.0 : 16.0
        return Rect(x: g.x - pad, y: g.y - pad, w: g.w + 2 * pad, h: g.h + 2 * pad)
    }

    /// The monument tries the centre first. Buildings then scan the whole grid from a random spot, so a district always
    /// gets its 7 casitas if they fit at all (random tries leave gaps too small for the last ones); decoration only tries
    /// random spots.
    private func findRoom(_ size: Vec, _ kind: Building.Kind, in district: Rect, avoiding rooms: [Rect],
                          _ rng: inout SeededRNG) -> Rect? {
        let s = Terrain.cell, inset = 40.0
        let c0 = Int(((district.x + inset - origin.x) / s).rounded(.up)), r0 = Int(((district.y + inset - origin.y) / s).rounded(.up))
        let c1 = Int(((district.x + district.w - inset - size.x - origin.x) / s).rounded(.down))
        let r1 = Int(((district.y + district.h - inset - size.y - origin.y) / s).rounded(.down))
        guard c0 <= c1, r0 <= r1 else { return nil }
        func at(_ c: Int, _ r: Int) -> Rect { Rect(x: origin.x + Double(c) * s, y: origin.y + Double(r) * s, w: size.x, h: size.y) }
        func fits(_ r: Rect) -> Bool {
            let room = Terrain.room(r, kind)
            guard room.y + room.h <= district.y + district.h, !rooms.contains(where: { $0.intersects(room) }) else { return false }
            return plain(Terrain.ground(r, kind), paths: kind == .monument)
        }
        if kind == .monument {
            let c = district.center
            let centre = at(Int(((c.x - size.x / 2 - origin.x) / s).rounded()), Int(((c.y - size.y / 2 - origin.y) / s).rounded()))
            if fits(centre) { return centre }
        }
        if kind.isDecoration {
            for _ in 0..<300 {
                let r = at(Int.random(in: c0...c1, using: &rng), Int.random(in: r0...r1, using: &rng))
                if fits(r) { return r }
            }
            return nil
        }
        let w = c1 - c0 + 1, n = w * (r1 - r0 + 1), k0 = Int.random(in: 0..<n, using: &rng)
        for k in 0..<n {
            let r = at(c0 + (k0 + k) % n % w, r0 + (k0 + k) % n / w)
            if fits(r) { return r }
        }
        return nil
    }

    /// Every cell `r` overlaps is walkable ground, and no path unless `paths`. A plain loop: placement tries it thousands of times.
    private func plain(_ r: Rect, paths: Bool) -> Bool {
        let s = Terrain.cell
        let c0 = max(0, Int(((r.x - origin.x) / s).rounded(.down))), r0 = max(0, Int(((r.y - origin.y) / s).rounded(.down)))
        let c1 = min(cols - 1, Int(((r.x + r.w - origin.x) / s).rounded(.up)) - 1)
        let r1 = min(rows - 1, Int(((r.y + r.h - origin.y) / s).rounded(.up)) - 1)
        guard c0 <= c1, r0 <= r1 else { return true }
        for row in r0...r1 {
            for c in c0...c1 {
                let cell = cells[row * cols + c]
                if !cell.walkable || (cell == .path && !paths) { return false }
            }
        }
        return true
    }

    /// The index of every cell `r` overlaps.
    private func cellIndices(_ r: Rect) -> [Int] {
        let s = Terrain.cell
        let c0 = max(0, Int(((r.x - origin.x) / s).rounded(.down))), r0 = max(0, Int(((r.y - origin.y) / s).rounded(.down)))
        let c1 = min(cols - 1, Int(((r.x + r.w - origin.x) / s).rounded(.up)) - 1)
        let r1 = min(rows - 1, Int(((r.y + r.h - origin.y) / s).rounded(.up)) - 1)
        guard c0 <= c1, r0 <= r1 else { return [] }
        return (r0...r1).flatMap { row in (c0...c1).map { row * cols + $0 } }
    }
}

extension World {
    /// The buildings and decoration of `district`, its place in `districts` (like `Bichito.district`).
    func buildings(in district: Int) -> [Building] {
        let theme = districts[district].index
        return terrain.buildings.filter { $0.theme == theme }
    }

    func building(_ id: Int) -> Building? {
        let all = terrain.buildings
        return all.indices.contains(id) ? all[id] : nil
    }

    /// Who lives in the casita `id` (at most 2), by bichito id.
    func occupants(of id: Int) -> [Int] { bichitos.filter { $0.home == id }.map(\.id) }

    /// The casita of its district with the fewest owners, while one has room for 2; none otherwise (it sleeps under a tree).
    /// Called whenever it arrives in a district: added, hatched, moved or back from running away.
    mutating func findHome(_ i: Int) {
        let theme = districts[bichitos[i].district].index, me = bichitos[i].id
        var best: (id: Int, n: Int)? = nil
        for c in terrain.buildings where c.kind == .casita && c.theme == theme {
            let n = bichitos.filter { $0.id != me && $0.home == c.id }.count
            if n < 2 && n < (best?.n ?? 2) { best = (c.id, n) }
        }
        bichitos[i].home = best?.id
    }

    /// Someone left `district` or ran away: whoever there had no casita tries again, so `home == nil` always means no room
    /// (and loading a save, `fitHomes`, gives nobody a new one).
    mutating func rehome(in district: Int) {
        for j in bichitos.indices where bichitos[j].home == nil && bichitos[j].district == district { findHome(j) }
    }

    /// For loaded saves: keeps every home that is still a casita of its owner's district with room,
    /// and finds one for the rest (saves from before casitas have none at all).
    mutating func fitHomes() {
        let all = terrain.buildings
        var owners: [Int: Int] = [:]
        for i in bichitos.indices {
            if let h = bichitos[i].home, all.indices.contains(h), all[h].kind == .casita,
               all[h].theme == districts[bichitos[i].district].index, owners[h, default: 0] < 2 {
                owners[h, default: 0] += 1
            } else {
                bichitos[i].home = nil
            }
        }
        for i in bichitos.indices where bichitos[i].home == nil { findHome(i) }
    }
}

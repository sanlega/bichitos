import Foundation

/// The ground of the whole ring (DESIGN.md, "Terreno"): one cell of 8 u (16 world units) per placement-grid square,
/// plus the paths as polylines for painting. A pure function of the layout seed, so it is never saved:
/// `World.terrain` regenerates it (once per seed, cached).
struct Terrain {
    enum Cell: UInt8 {
        case mist, meadow, sand, rock, water, path
        /// Water and rock are never walked on.
        var walkable: Bool { self != .rock && self != .water }
    }

    static let cell = 16.0      // 8 u
    static let pathWidth = 48.0 // 24 u
    static let blob = 4         // cells: obstacles are unions of 4×4 blocks (32 u), so no bend is tighter than 16 u

    /// World position of cell (0, 0)'s top-left corner; cell (c, r) is `cells[r * cols + c]`.
    let origin: Vec
    let cols: Int, rows: Int
    let cells: [Cell]
    /// Straight from Plaza Mayor's fountain to each themed district's centre, crossing its entrance and the mist between.
    let paths: [[Vec]]

    /// What is under `p`; mist outside the ring. O(1) and allocation-free: it runs for every body on every tick.
    func at(_ p: Vec) -> Cell {
        let fx = (p.x - origin.x) / Terrain.cell, fy = (p.y - origin.y) / Terrain.cell
        guard fx >= 0, fy >= 0, fx < Double(cols), fy < Double(rows) else { return .mist }
        return cells[Int(fy) * cols + Int(fx)]
    }

    func walkable(_ p: Vec) -> Bool { at(p).walkable }

    /// `p` itself when walkable, else the centre of the closest walkable cell, searched in square rings outwards.
    func nearestWalkable(_ p: Vec) -> Vec {
        guard !walkable(p) else { return p }
        let c0 = Int((p.x - origin.x) / Terrain.cell), r0 = Int((p.y - origin.y) / Terrain.cell) // inside: mist is walkable
        for k in 1..<max(cols, rows) {
            var best = p, bestD = Double.infinity
            for dr in -k...k {
                for dc in -k...k where abs(dr) == k || abs(dc) == k {
                    let c = c0 + dc, r = r0 + dr
                    guard c >= 0, r >= 0, c < cols, r < rows, cells[r * cols + c].walkable else { continue }
                    let q = Vec(origin.x + (Double(c) + 0.5) * Terrain.cell, origin.y + (Double(r) + 0.5) * Terrain.cell)
                    let d = (q - p).length
                    if d < bestD { bestD = d; best = q }
                }
            }
            if bestD < .infinity { return best }
        }
        return p
    }

    /// Each district's blobs come from smooth noise seeded by the district, biased by its dominant terrain;
    /// then the star of paths is laid over everything.
    init(seed: UInt64) {
        let rects = World.layout(seed: seed), size = Terrain.cell
        let x0 = rects.map(\.x).min()!, y0 = rects.map(\.y).min()!
        let x1 = rects.map { $0.x + $0.w }.max()!, y1 = rects.map { $0.y + $0.h }.max()!
        origin = Vec(x0, y0)
        cols = Int(((x1 - x0) / size).rounded(.up))
        rows = Int(((y1 - y0) / size).rounded(.up))
        var cells = [Cell](repeating: .mist, count: cols * rows)
        var raw = [Bool](repeating: false, count: cols * rows) // obstacle before smoothing
        var obstacle = [Cell](repeating: .mist, count: cols * rows)
        func centre(_ c: Int, _ r: Int) -> Vec { Vec(x0 + (Double(c) + 0.5) * size, y0 + (Double(r) + 0.5) * size) }

        for (t, rect) in rects.enumerated() {
            let look = Terrain.look(District.themes[t].terrain)
            let s = seed ^ (UInt64(t + 1) &* 0xD1B5_4A32_D192_ED03)
            for r in 0..<rows {
                for c in 0..<cols {
                    let p = centre(c, r)
                    guard rect.contains(p) else { continue }
                    let q = p - Vec(rect.x, rect.y), k = r * cols + c
                    cells[k] = Terrain.noise(q, s, 0) > 0.6 ? look.other : look.base
                    // Kept clear of the edges, wider than any body: whatever the walls clamp stays walkable.
                    let edge = min(q.x, q.y, rect.w - q.x, rect.h - q.y)
                    if let o = look.obstacle, edge > 40, Terrain.noise(q, s, 1) > look.threshold {
                        raw[k] = true
                        obstacle[k] = o
                    }
                }
            }
        }
        // Opening with a 4×4 block: only cells inside some all-obstacle block stay, so no specks, slivers or sharp tips.
        let b = Terrain.blob
        for r in 0...(rows - b) {
            for c in 0...(cols - b) {
                var full = true
                for dr in 0..<b where full { for dc in 0..<b where !raw[(r + dr) * cols + c + dc] { full = false } }
                guard full else { continue }
                for dr in 0..<b { for dc in 0..<b { cells[(r + dr) * cols + c + dc] = obstacle[(r + dr) * cols + c + dc] } }
            }
        }

        let fountain = rects[0].center
        paths = rects.dropFirst().map { [fountain, $0.center] }
        for r in 0..<rows {
            for c in 0..<cols {
                let p = centre(c, r)
                for path in paths where Terrain.distance(p, path[0], path[1]) <= Terrain.pathWidth / 2 {
                    cells[r * cols + c] = .path
                }
            }
        }
        self.cells = cells
    }

    /// A district's dominant terrain as ground, the patches mixed into it, and its obstacle (nil: none at all).
    /// Plaza Mayor stays clear: sand around the fountain where every path starts.
    private static func look(_ t: District.Terrain) -> (base: Cell, other: Cell, obstacle: Cell?, threshold: Double) {
        switch t {
        case .sandStar: return (.sand, .meadow, nil, 1)
        case .puddles: return (.meadow, .sand, .water, 0.6)
        case .rockWalls: return (.sand, .meadow, .rock, 0.6)
        case .meadowHills: return (.meadow, .sand, .water, 0.75)
        case .circuit: return (.sand, .meadow, .rock, 0.75)
        case .shrubs: return (.meadow, .sand, .rock, 0.7)
        case .flowers: return (.meadow, .sand, .water, 0.7)
        }
    }

    /// Value noise in [0, 1): random values on a 48 u lattice, blended with smoothstep, so blobs are round, not boxy.
    private static func noise(_ p: Vec, _ seed: UInt64, _ layer: UInt64) -> Double {
        let g = 96.0, fx = p.x / g, fy = p.y / g
        let ix = Int(fx.rounded(.down)), iy = Int(fy.rounded(.down))
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        let tx = smooth(fx - Double(ix)), ty = smooth(fy - Double(iy))
        func v(_ x: Int, _ y: Int) -> Double {
            var rng = SeededRNG(seed: seed &+ layer &* 0x94D0_49BB_1331_11EB
                &+ UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(y)) &* 0xBF58_476D_1CE4_E5B9)
            return Double(rng.next() >> 11) / Double(1 << 53)
        }
        let top = v(ix, iy) + (v(ix + 1, iy) - v(ix, iy)) * tx
        let bottom = v(ix, iy + 1) + (v(ix + 1, iy + 1) - v(ix, iy + 1)) * tx
        return top + (bottom - top) * ty
    }

    private static func distance(_ p: Vec, _ a: Vec, _ b: Vec) -> Double {
        let ab = b - a, ap = p - a
        let t = min(1, max(0, (ap.x * ab.x + ap.y * ab.y) / (ab.x * ab.x + ab.y * ab.y)))
        return (ap - ab * t).length
    }
}

private let terrainLock = NSLock()
private var terrainCache: [UInt64: Terrain] = [:]

extension World {
    /// The ground under the ring, from the layout seed (the same one `layout` uses). Never saved, so old saves load as they are.
    var terrain: Terrain {
        let seed = layoutSeed ?? 0
        terrainLock.lock()
        defer { terrainLock.unlock() }
        if let t = terrainCache[seed] { return t }
        if terrainCache.count >= 16 { terrainCache.removeAll() }
        let t = Terrain(seed: seed)
        terrainCache[seed] = t
        return t
    }
}

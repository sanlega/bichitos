import SwiftUI

@main
struct BichitosApp: App {
    var body: some Scene {
        WindowGroup {
            PenView { scene in
                WorldView(scene: scene)
            }
            .preferredColorScheme(.light) // the night comes from the world, not the system
        }
    }
}

/// Starting worlds.
enum Terrarium {
    static func random() -> WorldScene {
        let seed = UInt64.random(in: 1...UInt64.max)
        return WorldScene(world: World(seed: seed)) { world, visible in
            var rng = SeededRNG(seed: seed)
            spawn(6, in: visible, world: &world, rng: &rng)
        }
    }

    static func screenshot() -> WorldScene {
        WorldScene(world: World(seed: 7, date: Date(timeIntervalSince1970: 1_800_000_000))) { w, v in
            // Fixed slots: 4 rows of bichitos, each tall enough for bubble + sprite + name, clear of the status bar,
            // then a row for the egg and the note, above the tray.
            func at(_ fx: Double, _ row: Int) -> Vec {
                Vec(v.x + fx * v.w, v.y + v.h * [0.21, 0.385, 0.565, 0.745, 0.83][row])
            }
            var rng = SeededRNG(seed: 7)
            let recipes = (0..<9).map { _ in Recipe.random(using: &rng) }
            // The love pair shares row 1 side by side, as far apart as love allows without walking (reach + 4), names level.
            let gap = recipes[2].radius + recipes[3].radius + 3.5
            let mid = at(0.5, 1), side = Vec(gap / 2, 0)
            let slots = [at(0.27, 3), at(0.27, 0), mid - side, mid + side, at(0.73, 0),
                         at(0.27, 2), at(0.73, 2), at(0.73, 3), at(0.7, 4)]
            for (r, p) in zip(recipes, slots) { w.add(r, at: p) }
            w.dropFood(at: at(0.58, 2) + Vec(0, 8))
            // The other four foods in free gaps, so the captures show all five in pixel art.
            for (kind, p) in [(Food.Kind.galleta, at(0.1, 1)), (.seta, at(0.5, 0)), (.croqueta, at(0.9, 1)), (.macarron, at(0.5, 3))] {
                w.dropFood(at: p + Vec(0, 8), kind: kind)
            }
            // Moods that don't walk, so nobody leaves its slot before the capture; long calm so encounters don't reshuffle them.
            for i in w.bichitos.indices { w.bichitos[i].calm = 600; w.bichitos[i].enter(.held, for: 0) }
            w.bichitos[1].needs.sleep = 0.1
            w.bichitos[1].enter(.sleep, for: 600)
            w.bichitos[2].enter(.love, for: 600, target: w.bichitos[3].id)
            w.bichitos[3].enter(.love, for: 600, target: w.bichitos[2].id)
            w.bichitos[4].enter(.happy, for: 600)
            w.bichitos[5].enter(.wander, for: 600)
            w.bichitos[5].dizzy = 600 // no steering while dizzy, and it starts still; long because the CI capture can come a minute late
            w.bichitos[6].needs.hunger = 0.2
            w.bichitos[7].needs = Bichito.Needs(hunger: 0.5, sleep: 0.4, affection: 0.2)
            // Its card (-screenshot-card) shows friends, rivals, parents and a child.
            w.bichitos[7].affinity = [w.bichitos[2].id: 0.8, w.bichitos[4].id: 0.4, w.bichitos[5].id: -0.6]
            w.bichitos[7].parents = [w.bichitos[2].id, w.bichitos[3].id]
            w.bichitos[6].parents = [w.bichitos[7].id]
            w.eggs.append(Egg(id: 9000, pos: at(0.3, 4), parents: [], recipe: recipes[0], hatchIn: 600))
            if CommandLine.arguments.contains("-screenshot-toast") { // the love pair's egg, then a birth queued behind it
                w.record(.eggLaid(w.bichitos[2].id, w.bichitos[3].id))
                w.record(.hatched(w.bichitos[6].id))
            }
            let ghost = w.bichitos.removeLast() // ran away: only its note is left
            w.notes.append(Note(pos: ghost.pos, text: Names.goodbye(name: ghost.name, seed: 1, language: w.language), bichito: ghost))
        }
    }

    /// The mist between Plaza Mayor and its right-hand neighbour, with a bichito packing up for the neighbour.
    static func border() -> WorldScene {
        var w = World(seed: 8, date: Date(timeIntervalSince1970: 1_800_000_000))
        let right = w.layout.firstIndex { $0.y == 0 && $0.x > 0 } ?? 1
        w.unlock(right)
        var rng = SeededRNG(seed: 8)
        let edge = World.districtSize.x + World.districtGap / 2, mid = World.districtSize.y / 2
        spawn(9, in: Rect(x: edge - 240, y: 0, w: 480, h: World.districtSize.y), world: &w, rng: &rng)
        for i in w.bichitos.indices { w.bichitos[i].calm = 600 }
        let leaving = w.bichitos.firstIndex { $0.district == 0 } ?? 0
        return WorldScene(world: w, focus: Vec(edge, mid)) { w, _ in
            w.bichitos[leaving].district = 1
            w.record(.emigrated(w.bichitos[leaving].id, 1)) // so the move gets its toast
        }
    }

    /// `-screenshot-away` (CI): a fixed world to fast-forward 3 h, so the "mientras no estabas" sheet has news.
    static func away() -> World {
        var w = World(seed: 7, date: Date(timeIntervalSince1970: 1_800_000_000))
        var rng = SeededRNG(seed: 7)
        spawn(9, in: w.districts[0].rect, world: &w, rng: &rng)
        return w
    }

    /// Spreads bichitos over a jittered grid inside the visible rect, clear of the status bar and the bottom edge.
    static func spawn(_ count: Int, in r: Rect, world: inout World, rng: inout SeededRNG) {
        let columns = 3, rows = (count + columns - 1) / columns
        let top = r.y + 120, bottom = r.y + r.h - 120
        for k in 0..<count {
            let fx = (Double(k % columns) + 0.5) / Double(columns)
            let fy = (Double(k / columns) + 0.5) / Double(rows)
            let p = Vec(r.x + fx * r.w + .random(in: -20...20, using: &rng),
                        top + fy * (bottom - top) + .random(in: -20...20, using: &rng))
            world.add(Recipe.random(using: &rng), at: p)
        }
    }
}

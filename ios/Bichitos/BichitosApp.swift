import SwiftUI

@main
struct BichitosApp: App {
    // `-screenshot` (CI) starts a fixed, staged world so the captured screen is always the same;
    // `-border` stages the edge between two districts instead.
    @State private var scene = CommandLine.arguments.contains("-border") ? Terrarium.border()
        : CommandLine.arguments.contains("-screenshot") ? Terrarium.screenshot() : Terrarium.random()

    var body: some Scene {
        WindowGroup {
            WorldView(scene: scene)
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
        WorldScene(world: World(seed: 7, date: Date(timeIntervalSince1970: 1_800_000_000))) { w, visible in
            var rng = SeededRNG(seed: 7)
            spawn(9, in: visible, world: &w, rng: &rng)
            // Show off a few faces and bubbles; long calm so encounters don't reshuffle them before the capture.
            for i in w.bichitos.indices { w.bichitos[i].calm = 600 }
            w.bichitos[1].needs.sleep = 0.1
            w.bichitos[1].enter(.sleep, for: 600)
            w.bichitos[2].enter(.love, for: 600, target: w.bichitos[3].id)
            w.bichitos[3].enter(.love, for: 600, target: w.bichitos[2].id)
            w.bichitos[4].enter(.happy, for: 600)
            w.bichitos[5].dizzy = 30
            w.bichitos[6].needs.hunger = 0.2
            w.bichitos[7].needs = Bichito.Needs(hunger: 0.5, sleep: 0.4, affection: 0.2)
            let center = visible.center
            w.dropFood(at: Vec(center.x + 60, center.y + 40))
            w.eggs.append(Egg(id: 9000, pos: Vec(center.x - 90, visible.y + visible.h - 140), parents: [],
                              recipe: w.bichitos[0].recipe, hatchIn: 600))
            let ghost = w.bichitos.removeLast() // ran away: only its note is left
            w.notes.append(Note(pos: Vec(center.x + 100, visible.y + visible.h - 150),
                                text: Names.goodbye(name: ghost.name, seed: 1, language: w.language), bichito: ghost))
        }
    }

    /// The edge between the first two districts, with a bichito packing up for the second one.
    static func border() -> WorldScene {
        var w = World(seed: 8, date: Date(timeIntervalSince1970: 1_800_000_000))
        w.districts.append(District(index: 1))
        var rng = SeededRNG(seed: 8)
        let edge = World.districtSize.x
        spawn(9, in: Rect(x: edge - 140, y: 400, w: 280, h: 800), world: &w, rng: &rng)
        for i in w.bichitos.indices { w.bichitos[i].calm = 600 }
        let leaving = w.bichitos.firstIndex { $0.district == 0 } ?? 0
        return WorldScene(world: w, focus: Vec(edge, 800)) { w, _ in
            w.bichitos[leaving].district = 1 // after the scene noted its old home, so the move is announced
        }
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

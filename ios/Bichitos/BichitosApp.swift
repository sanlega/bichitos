import SpriteKit
import SwiftUI

@main
struct BichitosApp: App {
    // `-screenshot` (CI) starts a fixed, staged world so the captured screen is always the same.
    @State private var scene = CommandLine.arguments.contains("-screenshot") ? Terrarium.screenshot() : Terrarium.random()

    var body: some Scene {
        WindowGroup {
            WorldView(scene: scene)
        }
    }
}

/// The world on screen with its sheets. Self-contained, so it can sit inside any wrapper that owns the scene.
struct WorldView: View {
    let scene: WorldScene
    @State private var creating = false
    @State private var card: Int? // id of the bichito whose card is open

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .sheet(isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } })) {
                    if let card { BichitoCard(scene: scene, id: card) }
                }
            // shortcut: temporary entry point; when the bottom tray's "new bichito" button lands, it calls openCreator and this goes.
            Button(action: openCreator) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white).shadow(color: Color.ink.opacity(0.08), radius: 8, y: 4))
            }
            .accessibilityLabel("Nuevo bichito")
            .padding(16)
        }
        .sheet(isPresented: $creating) {
            CreatorSheet(seed: CommandLine.arguments.contains("-screenshot") ? 11 : .random(in: 1...UInt64.max),
                         language: scene.world.language) { recipe, name, description in
                scene.drop(recipe, name: name, description: description)
            }
        }
        .onAppear {
            scene.onLongPress = { card = $0 }
            if CommandLine.arguments.contains("-screenshot-editor") { openCreator() }
            if CommandLine.arguments.contains("-screenshot-card") {
                // After the staged world is populated: the one with friends, rivals and family.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { card = scene.world.bichitos.first { !$0.affinity.isEmpty }?.id }
            }
        }
    }

    /// Opens the editor; Soltar drops the new bichito into the world.
    func openCreator() { creating = true }
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
            // Its card (-screenshot-card) shows friends, rivals, parents and a child.
            w.bichitos[7].affinity = [w.bichitos[2].id: 0.8, w.bichitos[4].id: 0.4, w.bichitos[5].id: -0.6]
            w.bichitos[7].parents = [w.bichitos[2].id, w.bichitos[3].id]
            w.bichitos[6].parents = [w.bichitos[7].id]
            let center = visible.center
            w.dropFood(at: Vec(center.x + 60, center.y + 40))
            w.eggs.append(Egg(id: 9000, pos: Vec(center.x - 90, visible.y + visible.h - 140), parents: [],
                              recipe: w.bichitos[0].recipe, hatchIn: 600))
            let ghost = w.bichitos.removeLast() // ran away: only its note is left
            w.notes.append(Note(pos: Vec(center.x + 100, visible.y + visible.h - 150),
                                text: Names.goodbye(name: ghost.name, seed: 1, language: w.language), bichito: ghost))
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

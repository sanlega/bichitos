import XCTest
@testable import Bichitos

final class SimTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func world(seed: UInt64, count: Int) -> World {
        var w = World(seed: seed, date: start)
        var rng = SeededRNG(seed: seed)
        for _ in 0..<count { w.add(Recipe.random(using: &rng)) }
        return w
    }

    private func recipe(_ p: Recipe.Personality, seed: UInt64) -> Recipe {
        var rng = SeededRNG(seed: seed)
        var r = Recipe.random(using: &rng)
        r.personality = p
        return r
    }

    func testSameSeedGivesSameWorld() {
        var a = world(seed: 3, count: 25), b = world(seed: 3, count: 25)
        let half = Rect(x: 0, y: 0, w: 500, h: 800) // exercise both the on-screen and the off-screen paths
        a.visibleRect = half
        b.visibleRect = half
        for _ in 0..<3000 { a.tick(); b.tick() }
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.bichitos.map(\.pos), world(seed: 3, count: 25).bichitos.map(\.pos))
    }

    func testBodiesStayInsideTheMap() {
        var w = world(seed: 5, count: 30)
        XCTAssertGreaterThanOrEqual(w.districts.count, 3) // 14 per district
        w.visibleRect = Rect(x: 0, y: 0, w: w.size.x, h: w.size.y)
        for (k, b) in w.bichitos.enumerated() where k % 3 == 0 {
            w.grab(b.id)
            w.release(b.id, velocity: Vec(3000, -2500))
        }
        w.scare(at: Vec(500, 800))
        var outside = 0
        for t in 0..<4000 {
            if t == 2000 { w.visibleRect = nil }
            w.tick()
            for b in w.bichitos {
                let r = b.recipe.radius - 1e-6
                if b.pos.x < r || b.pos.y < r || b.pos.x > w.size.x - r || b.pos.y > w.size.y - r { outside += 1 }
            }
        }
        XCTAssertEqual(outside, 0)
    }

    func testHungryBichitoWalksToFoodAndEats() {
        var w = World(seed: 9, date: start)
        let id = w.add(recipe(.dormilona, seed: 1), at: Vec(200, 200))
        w.bichitos[0].needs.hunger = 0.2
        let food = Vec(500, 260)
        w.dropFood(at: food, kind: w.bichitos[0].favorite)
        XCTAssertEqual(w.bichitos[0].mood, .eat)
        let before = (w.bichitos[0].pos - food).length
        for _ in 0..<40 { w.tick() }
        XCTAssertLessThan((w.bichitos[0].pos - food).length, before)
        for _ in 0..<1200 where !w.foods.isEmpty { w.tick() }
        XCTAssertTrue(w.foods.isEmpty)
        XCTAssertEqual(w.bichito(id)?.needs.hunger ?? 0, 1, accuracy: 0.01)
    }

    func testTerritorialCanPickAFightAndHoldsAGrudge() {
        var fought = false
        for seed in UInt64(1)...40 where !fought {
            var w = World(seed: seed, date: start)
            let a = w.add(recipe(.territorial, seed: seed), at: Vec(300, 300))
            let b = w.add(recipe(.curiosa, seed: seed + 100), at: Vec(320, 300))
            for _ in 0..<40 { w.tick() }
            guard w.events.contains(.fought(a, b)) else { continue }
            fought = true
            XCTAssertLessThan(w.bichito(a)?.affinity[b] ?? 0, 0)
            XCTAssertLessThan(w.bichito(b)?.affinity[a] ?? 0, 0)
        }
        XCTAssertTrue(fought)
    }

    func testChildGenesComeFromParents() {
        var rng = SeededRNG(seed: 11)
        var mutated = 0
        for _ in 0..<300 {
            let a = Recipe.random(using: &rng), b = Recipe.random(using: &rng)
            let c = Recipe.child(of: a, and: b, using: &rng)
            let foreign = [
                c.body != a.body && c.body != b.body,
                c.eyes != a.eyes && c.eyes != b.eyes,
                c.legs != a.legs && c.legs != b.legs,
                c.palette != a.palette && c.palette != b.palette,
                c.personality != a.personality && c.personality != b.personality,
            ].filter { $0 }.count
            XCTAssertLessThanOrEqual(foreign, 1)
            mutated += foreign
            let fine: [(Double, Double, Double)] = [
                (c.roundness, a.roundness, b.roundness), (c.height, a.height, b.height), (c.bumps, a.bumps, b.bumps),
                (c.eyeSize, a.eyeSize, b.eyeSize), (c.eyeSpacing, a.eyeSpacing, b.eyeSpacing), (c.legLength, a.legLength, b.legLength),
            ]
            for (x, y, z) in fine {
                XCTAssert(x >= 0 && x <= 1)
                XCTAssert(x >= min(y, z) - Recipe.fineMutation - 1e-9 && x <= max(y, z) + Recipe.fineMutation + 1e-9)
            }
            XCTAssert(Recipe.legOptions.contains(c.legs))
            XCTAssert((0..<Recipe.paletteCount).contains(c.palette))
            XCTAssertEqual(c.engine, Recipe.currentEngine)
        }
        XCTAssertGreaterThan(mutated, 0)
        XCTAssertLessThan(mutated, 60)
    }

    func testLoversLayAnEggThatHatches() {
        var hatched = false
        for seed in UInt64(1)...20 where !hatched {
            var w = World(seed: seed, date: start)
            let a = w.add(recipe(.romantica, seed: seed), at: Vec(300, 300))
            let b = w.add(recipe(.romantica, seed: seed + 50), at: Vec(320, 300))
            w.bichitos[0].affinity[b] = 0.9
            w.bichitos[1].affinity[a] = 0.9
            for _ in 0..<5000 { w.tick() }
            for case let .hatched(c) in w.events {
                guard let child = w.bichito(c) else { continue }
                hatched = true
                XCTAssertEqual(Set(child.parents), [a, b])
                XCTAssertEqual(child.recipe.engine, Recipe.currentEngine)
                XCTAssertTrue(w.events.contains(.eggLaid(a, b)) || w.events.contains(.eggLaid(b, a)))
            }
        }
        XCTAssertTrue(hatched)
    }

    func testNeglectedBichitoEscapesAndFoodAtTheNoteBringsItBack() {
        var w = world(seed: 13, count: 1)
        let id = w.bichitos[0].id
        w.catchUp(seconds: 3 * 86400)
        XCTAssertNil(w.bichito(id))
        XCTAssertEqual(w.notes.count, 1)
        XCTAssertTrue(w.events.contains(.escaped(id)))
        XCTAssertTrue(w.notes[0].text.hasSuffix(w.notes[0].bichito.name))
        print("Note: \(w.notes[0].text)")
        let favorite = w.notes[0].bichito.favorite
        let other = Food.Kind.allCases.first { $0 != favorite }!
        w.dropFood(at: w.notes[0].pos + Vec(10, 0), kind: other)
        XCTAssertEqual(w.notes.count, 1, "only its favourite brings it back")
        w.dropFood(at: w.notes[0].pos + Vec(w.notes[0].pos.x < 500 ? 200 : -200, 0), kind: favorite)
        XCTAssertEqual(w.notes.count, 1, "it has to be next to the note")
        w.dropFood(at: w.notes[0].pos + Vec(10, 0), kind: favorite)
        XCTAssertTrue(w.notes.isEmpty)
        XCTAssertNotNil(w.bichito(id))
        XCTAssertTrue(w.events.contains(.recovered(id)))
    }

    func testWeekLongCatchUpTerminatesAndAppliesNeeds() {
        var week = world(seed: 17, count: 10)
        week.catchUp(seconds: 30 * 86400) // clamped to 7 days
        XCTAssertEqual(week.date.timeIntervalSince(start), 7 * 86400, accuracy: 1)
        XCTAssertTrue(week.bichitos.isEmpty)
        XCTAssertEqual(week.notes.count, 10)

        var day = world(seed: 17, count: 10)
        day.catchUp(seconds: 86400)
        XCTAssertFalse(day.bichitos.isEmpty)
        for b in day.bichitos where b.parents.isEmpty { XCTAssertLessThan(b.needs.hunger, 0.5) }
        let lines = day.summary(.es)
        XCTAssertFalse(lines.isEmpty)
        print("Mientras no estabas: " + lines.joined(separator: " "))
        print("While you were away: " + day.summary(.en).joined(separator: " "))
    }

    func testTwoHourCatchUpWithFortyBichitosIsFast() {
        var w = world(seed: 21, count: 40)
        let t0 = Date()
        w.catchUp(seconds: 2 * 3600)
        let elapsed = Date().timeIntervalSince(t0)
        print("CATCHUP 2h x 40 bichitos: \(String(format: "%.3f", elapsed)) s, \(w.bichitos.count) bichitos, \(w.events.count) events")
        // Debug build on a shared CI simulator: ~3 s here, and it swings with runner load; a real regression still trips 6.
        XCTAssertLessThan(elapsed, 6, "catchUp took \(elapsed) s")
    }

    func testWhereCatchUpTimeGoes() {
        var w = world(seed: 21, count: 40)
        Profile.reset()
        w.catchUp(seconds: 2 * 3600)
        print("PROFILE 2h x 40 bichitos:
" + Profile.report)
    }

    /// FNV-1a over everything the simulation moves, Doubles by bit pattern, so any change in behaviour shows.
    /// Recorded before the #65 optimisation; re-record it only when the simulation changes on purpose.
    private func stateHash(_ w: World) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ v: UInt64) { for k in 0..<8 { h = (h ^ ((v >> UInt64(8 * k)) & 0xff)) &* 0x0000_0100_0000_01b3 } }
        func d(_ x: Double) { mix(x.bitPattern) }
        func i(_ x: Int) { mix(UInt64(bitPattern: Int64(x))) }
        func s(_ x: String) { for b in x.utf8 { mix(UInt64(b)) }; mix(0) }
        func v(_ p: Vec) { d(p.x); d(p.y) }
        i(w.tickCount); i(w.nextId); mix(w.rng.state); d(w.date.timeIntervalSince1970)
        for x in w.districts { i(x.index) }
        for b in w.bichitos {
            i(b.id); s(b.name); v(b.pos); v(b.vel); d(b.heading); s(b.mood.rawValue); d(b.timer); i(b.target ?? -1)
            v(b.threat ?? Vec(-1, -1)); d(b.needs.hunger); d(b.needs.sleep); d(b.needs.affection)
            for k in b.affinity.keys.sorted() { i(k); d(b.affinity[k]!) }
            i(b.district); d(b.dizzy); d(b.calm); d(b.breedCooldown); for p in b.parents { i(p) }
        }
        for f in w.foods { i(f.id); v(f.pos); s(f.kind.rawValue) }
        for e in w.eggs { i(e.id); v(e.pos); d(e.hatchIn); mix(e.recipe.seed); for p in e.parents { i(p) } }
        for n in w.notes { v(n.pos); s(n.text); i(n.bichito.id) }
        for e in w.events { s("\(e)") }
        for n in w.news.items { s("\(n.event)"); i(n.count); d(n.date.timeIntervalSince1970); v(n.place) }
        return String(h, radix: 16)
    }

    func testOptimisationKeepsTheSameWorld() {
        var w = world(seed: 3, count: 40)
        w.visibleRect = Rect(x: 0, y: 0, w: 1200, h: 900) // on-screen path with collisions and bonks, too
        w.dropFood(at: Vec(400, 400))
        for _ in 0..<6000 { w.tick() }
        w.visibleRect = nil
        w.catchUp(seconds: 1800)
        let hash = stateHash(w)
        print("STATE HASH: \(hash), \(w.bichitos.count) bichitos, \(w.events.count) events, \(w.eggs.count) eggs")
        XCTAssertEqual(hash, "record-me")
    }

    func testWorldSurvivesSaving() throws {
        var w = world(seed: 23, count: 15)
        for _ in 0..<2000 { w.tick() }
        w.dropFood(at: Vec(100, 100))
        w.bichitos[0].needs = Bichito.Needs(hunger: 0, sleep: 1, affection: 0)
        for _ in 0..<40 { w.tick() }
        XCTAssertFalse(w.notes.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(World.self, from: JSONEncoder().encode(w)), w)

        let pen = Pen(url: FileManager.default.temporaryDirectory.appendingPathComponent("pen-test.json"))
        try pen.save(w, at: start)
        let saved = try XCTUnwrap(pen.load())
        XCTAssertEqual(saved.world, w)
        XCTAssertEqual(saved.lastSaved, start)
    }

    func testNamesAreDeterministicAndBilingual() {
        XCTAssertEqual(Names.make(seed: 5, language: .es).description, Names.make(seed: 5, language: .es).description)
        XCTAssertTrue(Names.make(seed: 5, language: .es).description.contains("año"))
        XCTAssertTrue(Names.make(seed: 5, language: .en).description.contains("old"))
        XCTAssertGreaterThanOrEqual(min(Names.namesEs.count, Names.namesEn.count), 30)
        XCTAssertGreaterThanOrEqual(min(Names.quirksEs.count, Names.quirksEn.count), 40)
        print((UInt64(1)...5).map { Names.make(seed: $0, language: .es).description }.joined(separator: " | "))
    }
}

import XCTest
@testable import Bichitos

final class BarriosTests: XCTestCase {
    func testSevenThemedDistricts() {
        let t = District.themes
        XCTAssertEqual(t.count, 7)
        XCTAssertEqual(t[0].es, "Plaza Mayor")
        XCTAssertNil(t[0].affine, "Plaza Mayor is home to nobody in particular")
        XCTAssertEqual(Set(t.dropFirst().compactMap(\.affine)), Set(Recipe.Personality.allCases))
        XCTAssertEqual(t.dropFirst().compactMap(\.affine).count, 6, "one district per personality")
        XCTAssertEqual(Set(t.map(\.es)).count, 7)
        XCTAssertEqual(Set(t.map(\.en)).count, 7)
        XCTAssertEqual(World.capacity, 14)
        XCTAssertEqual(World.maxPopulation, 98)
        XCTAssertEqual(District(index: 3).name(.en), "Pillowville")
    }

    func testDistrictsStopAtSeven() {
        var w = World(testSeed: 2, date: Date(timeIntervalSince1970: 1_700_000_000))
        var rng = SeededRNG(seed: 2)
        for _ in 0..<110 { w.add(Recipe.random(using: &rng)) }
        XCTAssertEqual(w.districts.count, 7)
        XCTAssertEqual(Set(w.districts.map(\.index)), Set(0..<7))
    }

    func testRingLayoutIsDeterministicAndNeverOverlaps() {
        XCTAssertEqual(World.layout(seed: 5), World.layout(seed: 5))
        XCTAssertTrue((UInt64(1)...20).contains { World.layout(seed: $0) != World.layout(seed: 5) }, "the seed places them")
        for seed: UInt64 in [1, 5, 99, .max] {
            let rs = World.layout(seed: seed)
            XCTAssertEqual(rs.count, 7)
            XCTAssertEqual(rs[0], Rect(x: 0, y: 0, w: World.districtSize.x, h: World.districtSize.y), "Plaza Mayor in the centre")
            for (i, a) in rs.enumerated() {
                XCTAssertEqual(a.w, World.districtSize.x)
                XCTAssertEqual(a.h, World.districtSize.y)
                XCTAssertLessThan((a.center - rs[0].center).length, 1.6 * World.districtSize.x, "next to the plaza")
                for b in rs[(i + 1)...] {
                    let apart = max(b.x - (a.x + a.w), a.x - (b.x + b.w), b.y - (a.y + a.h), a.y - (b.y + b.h))
                    XCTAssertGreaterThanOrEqual(apart, World.districtGap - 1e-9, "mist between every pair")
                }
            }
        }
        XCTAssertEqual(World(testSeed: 5).districts[0].rect, World.layout(seed: 5)[0])
    }

    private func recipe(_ p: Recipe.Personality, _ seed: UInt64) -> Recipe {
        var rng = SeededRNG(seed: seed)
        var r = Recipe.random(using: &rng)
        r.personality = p
        return r
    }

    func testMostlyTerritorialPopulationOpensLasEsquinas() {
        var w = World(testSeed: 4)
        let others = Recipe.Personality.allCases.filter { $0 != .territorial }
        for k in 0..<World.capacity { w.add(recipe(k < 9 ? .territorial : others[k % others.count], UInt64(k))) }
        let plaza = w.bounds
        XCTAssertEqual(w.districts.count, 1)
        w.add(recipe(.curiosa, 100)) // one too many
        XCTAssertEqual(w.districts.count, 2)
        XCTAssertEqual(w.districts[1].name(.es), "Las Esquinas")
        XCTAssertEqual(w.districts[1].rect, w.layout[2], "in its place of the ring")
        XCTAssertEqual(w.events.last, .unlocked(1, .territorial), "it says why it opened")
        XCTAssertNotEqual(w.bounds, plaza, "the map grows with it")
        let r = w.districts[1].rect, b = w.bounds
        XCTAssertTrue(b.contains(Vec(r.x, r.y)) && b.contains(Vec(r.x + r.w, r.y + r.h)) && b.contains(Vec(plaza.x, plaza.y)))
    }

    func testNobodyAffineStillOpensForRoom() {
        var w = World(testSeed: 4)
        for k in 0...World.capacity { w.add(recipe(.territorial, UInt64(k))) }
        XCTAssertEqual(w.districts.last?.name(.es), "Las Esquinas")
        while w.districts.count < 3 { w.add(recipe(.territorial, 999)) } // no other territorial district left
        XCTAssertEqual(w.districts[2].index, 1, "ties go to the first theme")
        XCTAssertEqual(w.events.last, .unlocked(2, nil))
    }

    /// A save from before design v2: 8 districts in a row, with bichitos, a note and events in the 8th one.
    func testOldEightDistrictSaveLoadsWithEveryone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pen = Pen(url: dir.appendingPathComponent("pen.json"), timeZone: World.daytime)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        var w = World(testSeed: 9, date: start)
        var rng = SeededRNG(seed: 9)
        for _ in 0..<20 { w.add(Recipe.random(using: &rng)) }
        try pen.save(w, at: start)

        // Rewrite it into the old shape.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pen.url)) as? [String: Any])
        var world = try XCTUnwrap(json["world"] as? [String: Any])
        world["districts"] = (0..<8).map { ["index": $0] }
        world["layoutSeed"] = nil
        var bichitos = try XCTUnwrap(world["bichitos"] as? [[String: Any]])
        for i in 0..<3 {
            bichitos[i]["district"] = 7
            bichitos[i]["pos"] = ["x": 7500.0, "y": 800.0]
        }
        bichitos[4]["district"] = 2
        bichitos[4]["pos"] = ["x": 2500.0, "y": 1200.0] // halfway across and three quarters down the third 1000×1600 cell
        let third = try XCTUnwrap(bichitos[4]["id"] as? Int)
        world["notes"] = [["pos": ["x": 7600.0, "y": 900.0], "text": "adiós", "bichito": bichitos[3].merging(["district": 7]) { $1 }]]
        world["bichitos"] = Array(bichitos[0..<3] + bichitos[4...])
        world["events"] = [["unlocked": ["_0": 7]], ["emigrated": ["_0": bichitos[0]["id"] as Any, "_1": 7]]]
        json["world"] = world
        try JSONSerialization.data(withJSONObject: json).write(to: pen.url)

        let loaded = try XCTUnwrap(try pen.load()?.world)
        XCTAssertEqual(loaded.districts.count, 7)
        XCTAssertEqual(loaded.bichitos.count, 19)
        XCTAssertEqual(loaded.notes.count, 1)
        XCTAssertEqual(Set(loaded.bichitos.map(\.id) + loaded.notes.map(\.bichito.id)), Set(w.bichitos.map(\.id)))
        XCTAssertEqual(loaded.districts.map(\.index), Array(0..<7))
        XCTAssertEqual(loaded.districts.map(\.rect), loaded.layout, "re-laid out in the ring")
        XCTAssertNotNil(loaded.layoutSeed)
        for b in loaded.bichitos + loaded.notes.map(\.bichito) {
            XCTAssertLessThan(b.district, 7)
            XCTAssertTrue(loaded.districts[b.district].rect.contains(b.pos), "everyone inside their district")
        }
        XCTAssertTrue(loaded.districts.contains { $0.rect.contains(loaded.notes[0].pos) })
        let moved = try XCTUnwrap(loaded.bichito(third)), r = loaded.districts[2].rect, radius = moved.recipe.radius
        XCTAssertEqual(moved.pos.x, r.x + radius + 0.5 * (r.w - 2 * radius), accuracy: 1e-9)
        XCTAssertEqual(moved.pos.y, r.y + radius + 0.75 * (r.h - 2 * radius), accuracy: 1e-9)
        XCTAssertTrue(loaded.events.isEmpty)
        var again = loaded
        again.fitDistricts()
        XCTAssertEqual(again, loaded, "a migrated save is left alone")

        let opened = try XCTUnwrap(pen.open(now: start + 600).world, "fast-forward and summary don't trip on it")
        XCTAssertGreaterThanOrEqual(opened.bichitos.count + opened.notes.count, 20) // a pair may breed meanwhile
    }
    // MARK: - Emigration

    private func world(seed: UInt64, count: Int, all personality: Recipe.Personality? = nil) -> World {
        var w = World(testSeed: seed, date: Date(timeIntervalSince1970: 1_700_000_000))
        var rng = SeededRNG(seed: seed)
        for _ in 0..<count {
            var r = Recipe.random(using: &rng)
            if let p = personality { r.personality = p }
            w.add(r)
        }
        return w
    }

    private func counts(_ w: World) -> [Int] {
        var c = Array(repeating: 0, count: w.districts.count)
        for b in w.bichitos { c[b.district] += 1 }
        return c
    }

    func testBichitosDriftToTheirAffineDistrictWhenThereIsRoom() {
        var w = world(seed: 29, count: 60) // 5 districts open, room for 70
        XCTAssertEqual(w.districts.count, 5)
        func atHome() -> Double {
            let homed = w.bichitos.filter { b in w.districts.contains { $0.theme.affine == b.recipe.personality } }
            return Double(homed.filter { w.districts[$0.district].theme.affine == $0.recipe.personality }.count) / Double(homed.count)
        }
        let before = atHome()
        for _ in 0..<200 { w.emigrate() }
        let after = atHome()
        XCTAssertGreaterThan(after, before + 0.3, "before \(before), after \(after)")
        XCTAssertGreaterThan(after, 0.7)
        XCTAssertTrue(counts(w).allSatisfy { $0 <= World.capacity })
    }

    func testNeverEmigratesToAFullDistrict() {
        var w = world(seed: 7, count: 60, all: .curiosa) // all want Villa Charco, which fits 14
        for _ in 0..<200 {
            w.emigrate()
            XCTAssertTrue(counts(w).allSatisfy { $0 <= World.capacity }, "\(counts(w))")
        }
        XCTAssertEqual(counts(w)[1], World.capacity, "it fills up, then nobody else gets in")
    }

    func testNeverEmigratesToALockedDistrict() {
        var w = world(seed: 8, count: 15, all: .curiosa) // opens Villa Charco, the curiosas' district
        var rng = SeededRNG(seed: 80)
        for _ in 0..<5 { var r = Recipe.random(using: &rng); r.personality = .dormilona; w.add(r) }
        XCTAssertEqual(w.districts.map(\.index), [0, 1], "Almohadilla (3) is still locked")
        for _ in 0..<200 { w.emigrate() }
        XCTAssertTrue(w.bichitos.allSatisfy { $0.district < 2 })
        XCTAssertEqual(w.districts.count, 2)
    }

    /// BarrioPicker: every district, open ones with their population, locked ones with how many bichitos they still need.
    func testPickerRows() {
        var w = World(testSeed: 3, date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(w.barrioRows.map(\.place), [0, nil, nil, nil, nil, nil, nil])
        XCTAssertEqual(w.bichitosToNextDistrict, 15)
        var rng = SeededRNG(seed: 3)
        for _ in 0..<20 { w.add(Recipe.random(using: &rng)) }
        let rows = w.barrioRows
        XCTAssertEqual(rows.map(\.theme), Array(0..<7))
        XCTAssertEqual(rows.compactMap(\.place).sorted(), [0, 1])
        XCTAssertEqual(rows.compactMap(\.place).map { w.districts[$0].index }, rows.filter { $0.place != nil }.map(\.theme))
        XCTAssertEqual(rows.map(\.population).reduce(0, +), 20)
        XCTAssertEqual(rows[0].population, w.bichitos.filter { $0.district == 0 }.count)
        for r in rows where r.place == nil {
            XCTAssertEqual(r.population, 0)
            XCTAssertEqual(r.fans, w.bichitos.filter { $0.recipe.personality == District.themes[r.theme].affine }.count)
        }
        // One number for the whole map, since which district opens depends on who lives here.
        XCTAssertEqual(w.bichitosToNextDistrict, 9)
        for _ in 0..<8 { w.add(Recipe.random(using: &rng)) }
        XCTAssertEqual(w.districts.count, 2)
        XCTAssertEqual(w.bichitosToNextDistrict, 1)
        w.add(Recipe.random(using: &rng))
        XCTAssertEqual(w.districts.count, 3, "the count shown is exactly what opens it")
        XCTAssertEqual(w.bichitosToNextDistrict, 14)

        for _ in 0..<80 { w.add(Recipe.random(using: &rng)) }
        XCTAssertNil(w.bichitosToNextDistrict, "all seven open")
        XCTAssertTrue(w.barrioRows.allSatisfy { $0.place != nil && $0.fans == 0 })
    }

    /// Tapping a district: the camera springs there, lands exactly on it and a pan takes over.
    func testCameraTravelsToADistrict() {
        var c = Camera(center: Vec(500, 800), scale: 3)
        let to = Vec(1500, 800)
        c.travel(to: to)
        c.glide(dt: 0.1)
        XCTAssertGreaterThan(c.center.x, 500)
        XCTAssertLessThan(c.center.x, to.x + 50, "damping 0.85 barely overshoots")
        for _ in 0..<120 { c.glide(dt: 1.0 / 60) }
        XCTAssertNil(c.trip)
        XCTAssertEqual(c.center, to)

        c.travel(to: Vec(0, 0))
        c.pan(by: Vec(1, 0))
        XCTAssertNil(c.trip)
    }

    /// Mapa level: every locked district is a dashed outline at its place in the ring; only the one that opens next says how many are missing.
    func testLockedOutlinesOnTheMap() {
        var w = world(seed: 9, count: 5, all: .dormilona)
        let locked = w.lockedOutlines
        XCTAssertEqual(locked.map(\.theme), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(locked.map(\.rect), Array(w.layout[1...]))
        XCTAssertEqual(locked.filter { $0.missing != nil }.map(\.theme), [3], "Almohadilla, the dormilonas' district")
        XCTAssertEqual(locked.first { $0.theme == 3 }?.missing, 10)
        w.unlock(3)
        XCTAssertFalse(w.lockedOutlines.map(\.theme).contains(3))
        for t in [1, 2, 4, 5, 6] { w.unlock(t) }
        XCTAssertEqual(w.lockedOutlines, [])
    }

    /// #38: a sign at each end of every open path, inside the district it names and beside the path, not on it.
    func testSignsAtEveryPathEntrance() {
        var w = world(seed: 9, count: 5, all: .dormilona)
        XCTAssertEqual(w.signs, [], "Plaza Mayor alone has no open path")
        for t in [3, 1, 6] { w.unlock(t) }
        let signs = w.signs, plaza = w.layout[0].center
        XCTAssertEqual(signs.count, 6)
        XCTAssertEqual(signs.filter { $0.theme == 0 }.count, 3, "Plaza Mayor's at each path out")
        XCTAssertEqual(Set(signs.map(\.theme)), [0, 3, 1, 6])
        for (k, s) in signs.enumerated() {
            XCTAssertTrue(w.layout[s.theme].contains(s.pos), "\(s) inside its district")
            let u = (w.layout[signs[k | 1].theme].center - plaza).unit, q = s.pos - plaza
            XCTAssertGreaterThan(abs(q.x * u.y - q.y * u.x), Terrain.pathWidth / 2, "\(s) beside its path")
        }
    }

    /// Mapa level: each bichito is a dot of its palette's base colour.
    func testMapDotIsThePaletteBase() {
        var rng = SeededRNG(seed: 4)
        var r = Recipe.random(using: &rng)
        var seen = Set<RGBA>()
        for i in 0..<Recipe.paletteCount {
            r.palette = i
            XCTAssertEqual(Look.dot(r), Palette.all[i].colors[3])
            seen.insert(Look.dot(r))
        }
        XCTAssertEqual(seen.count, Recipe.paletteCount, "every palette its own dot")
    }
}

import XCTest
@testable import Bichitos

final class EdificiosTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func world(seed: UInt64, count: Int) -> World {
        var w = World(seed: seed, date: start)
        var rng = SeededRNG(seed: seed)
        for _ in 0..<count { w.add(Recipe.random(using: &rng)) }
        return w
    }

    /// The centre of every cell `r` covers.
    private func cells(_ r: Rect) -> [Vec] {
        stride(from: r.x + 8, to: r.x + r.w, by: Terrain.cell).flatMap { x in
            stride(from: r.y + 8, to: r.y + r.h, by: Terrain.cell).map { Vec(x, $0) }
        }
    }

    func testPlacementIsDeterministic() {
        XCTAssertEqual(Terrain(seed: 5).buildings, Terrain(seed: 5).buildings)
        XCTAssertEqual(Terrain(seed: 5).blocked, Terrain(seed: 5).blocked)
        XCTAssertNotEqual(Terrain(seed: 5).buildings.map(\.rect), Terrain(seed: 6).buildings.map(\.rect))
    }

    func testEveryDistrictGetsItsBuildingsWithoutOverlapsOnPlainGround() {
        for seed in UInt64(1)...8 {
            let t = Terrain(seed: seed), rects = World.layout(seed: seed)
            XCTAssertEqual(t.buildings.map(\.id), Array(t.buildings.indices))
            for (theme, rect) in rects.enumerated() {
                let here = t.buildings.filter { $0.theme == theme }
                func count(_ k: Building.Kind) -> Int { here.filter { $0.kind == k }.count }
                XCTAssertEqual(count(.casita), 7, "seed \(seed) theme \(theme)")
                for k in [Building.Kind.comedero, .banco, .nido, .monument] {
                    XCTAssertEqual(count(k), 1, "\(k) seed \(seed) theme \(theme)")
                }
                XCTAssertGreaterThan(here.filter(\.kind.isDecoration).count, 5)
                if let m = here.first(where: { $0.kind == .monument }) { XCTAssert((192...256).contains(m.rect.w)) }
                for (k, b) in here.enumerated() {
                    XCTAssertTrue(cells(b.rect).allSatisfy(rect.contains), "\(b.kind) outside its district, seed \(seed)")
                    for p in cells(b.rect) {
                        let ground = t.at(p)
                        XCTAssertTrue(ground.walkable, "\(b.kind) on \(ground), seed \(seed)")
                        // The monument stands where the paths end, in the centre.
                        if b.kind != .monument { XCTAssertNotEqual(ground, .path, "\(b.kind) on a path, seed \(seed)") }
                    }
                    for o in here[(k + 1)...] { XCTAssertFalse(b.rect.intersects(o.rect), "\(b.kind) on \(o.kind), seed \(seed)") }
                    if let bed = b.bed { XCTAssertTrue(t.walkable(bed), "\(b.kind) bed blocked, seed \(seed)") }
                    XCTAssertEqual(b.door != nil, b.kind == .casita)
                }
            }
            let decoration = t.buildings.filter(\.kind.isDecoration).count
            print("BUILDINGS seed \(seed): \(t.buildings.count - decoration) buildings, \(decoration) decoration")
        }
    }

    func testFootprintsBlockWhereDesignSays() {
        let t = Terrain(seed: 3)
        for b in t.buildings {
            switch b.kind {
            case .casita, .monument, .rock, .fence, .tree:
                guard let s = b.blocks else { XCTFail("\(b.kind) should block"); continue }
                XCTAssertTrue(cells(s).allSatisfy { !t.walkable($0) }, "\(b.kind)")
                XCTAssertTrue(t.walkable(t.nearestWalkable(s.center)))
                if b.kind == .tree { XCTAssertEqual(s.w * s.h, 16 * 16, "only the trunk") }
                if b.kind == .casita { XCTAssertTrue(t.walkable(b.rect.center - Vec(0, b.rect.h / 2 - 8)), "behind it is walkable") }
            default:
                XCTAssertNil(b.blocks)
                XCTAssertTrue(cells(b.rect).allSatisfy(t.walkable), "\(b.kind) is walked through")
            }
        }
    }

    func testEachBichitoGetsACasitaOfItsDistrictAndAtMostTwoShare() {
        let w = world(seed: 8, count: 98) // every district open and full
        XCTAssertEqual(w.districts.count, 7)
        var owners: [Int: Int] = [:]
        for b in w.bichitos {
            guard let home = b.home.flatMap(w.building) else { XCTFail("\(b.name) has no casita"); continue }
            XCTAssertEqual(home.kind, .casita)
            XCTAssertEqual(home.theme, w.districts[b.district].index)
            owners[home.id, default: 0] += 1
        }
        XCTAssertTrue(owners.values.allSatisfy { $0 <= 2 })
        for d in w.districts.indices {
            for c in w.buildings(in: d) where c.kind == .casita { XCTAssertLessThanOrEqual(w.occupants(of: c.id).count, 2) }
        }

        // Moving frees the old casita and takes one in the new district.
        var v = world(seed: 9, count: 20)
        XCTAssertGreaterThanOrEqual(v.districts.count, 2)
        let id = v.bichitos.first { $0.district == 0 }!.id, old = v.bichito(id)!.home!
        v.bichitos.removeAll { $0.district == 1 && $0.id != id } // room for sure
        let j = v.index(of: id)!
        v.moveHome(j, to: 1)
        guard let new = v.bichitos[j].home.flatMap(v.building) else { return XCTFail("no casita after moving") }
        XCTAssertEqual(new.theme, v.districts[1].index)
        XCTAssertFalse(v.occupants(of: old).contains(id))
        XCTAssertEqual(v.occupants(of: new.id), [id])

        // Running away frees it too.
        var u = world(seed: 13, count: 1)
        let home = u.bichitos[0].home!
        u.catchUp(seconds: 3 * 86400)
        XCTAssertTrue(u.bichitos.isEmpty)
        XCTAssertTrue(u.occupants(of: home).isEmpty)
    }

    func testSleepersEndAtTheirDoorOrUnderATree() {
        var w = world(seed: 4, count: 14) // all in Plaza Mayor, 2 per casita
        w.bichitos[0].home = nil           // no casita: under a tree
        for i in w.bichitos.indices {
            w.bichitos[i].needs.sleep = 0.05
            w.bichitos[i].enter(.wander, for: 0)
        }
        for _ in 0..<2000 { w.tick() } // past the 90 s a walk to bed may take
        XCTAssertTrue(w.bichitos.allSatisfy { $0.mood == .sleep || $0.mood == .toBed }, "\(w.bichitos.map(\.mood))")
        let t = w.terrain
        let home = w.bichitos.dropFirst().filter { b in b.home.flatMap { t.buildings[$0].door }.map { (b.pos - $0).length < 48 } ?? false }
        print("BEDTIME: \(home.count) of 13 asleep at their door")
        XCTAssertGreaterThanOrEqual(home.count, 10)
        let trees = w.buildings(in: 0).filter { $0.kind == .tree }
        XCTAssertFalse(trees.isEmpty)
        XCTAssertTrue(trees.contains { ($0.bed! - w.bichitos[0].pos).length < 48 }, "the homeless one sleeps under a tree")
    }

    func testOldSavesGetHomesOnLoad() throws {
        let w = world(seed: 31, count: 30)
        var old = w
        for i in old.bichitos.indices { old.bichitos[i].home = nil } // what a save from before casitas looks like
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pen-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let pen = Pen(url: url)
        try pen.save(old, at: start)
        let json = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(json.contains("\"home\""))
        XCTAssertFalse(json.contains("buildings") || json.contains("blocked"), "buildings are not saved")
        let loaded = try XCTUnwrap(pen.load()).world
        XCTAssertEqual(loaded.bichitos.count, 30)
        XCTAssertEqual(loaded.bichitos.map(\.home), w.bichitos.map(\.home), "the same homes as when they were added")
        XCTAssertTrue(loaded.bichitos.allSatisfy { $0.home != nil })
    }
}

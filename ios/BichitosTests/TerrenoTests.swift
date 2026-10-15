import XCTest
@testable import Bichitos

final class TerrenoTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func world(seed: UInt64, count: Int) -> World {
        var w = World(seed: seed, date: start)
        var rng = SeededRNG(seed: seed)
        for _ in 0..<count { w.add(Recipe.random(using: &rng)) }
        return w
    }

    private func cells(_ t: Terrain, in r: Rect) -> [Terrain.Cell] {
        stride(from: r.x + 8, to: r.x + r.w, by: Terrain.cell).flatMap { x in
            stride(from: r.y + 8, to: r.y + r.h, by: Terrain.cell).map { t.at(Vec(x, $0)) }
        }
    }

    func testTerrainIsDeterministicAndFollowsEachDistrict() {
        let a = Terrain(seed: 5), b = Terrain(seed: 5), c = Terrain(seed: 6)
        XCTAssertEqual(a.cells, b.cells)
        XCTAssertEqual(a.paths, b.paths)
        XCTAssertNotEqual(a.cells, c.cells)
        let rects = World.layout(seed: 5)
        XCTAssertTrue(cells(a, in: rects[0]).allSatisfy(\.walkable), "Plaza Mayor is clear")
        let water = cells(a, in: rects[1]).filter { $0 == .water }.count, rock = cells(a, in: rects[2]).filter { $0 == .rock }.count
        print("TERRAIN seed 5: Villa Charco \(water) water cells, Las Esquinas \(rock) rock cells of \(cells(a, in: rects[1]).count)")
        XCTAssertGreaterThan(water, 0)
        XCTAssertGreaterThan(rock, 0)
        XCTAssertFalse(cells(a, in: rects[1]).contains(.rock))
        XCTAssertFalse(cells(a, in: rects[2]).contains(.water))
    }

    func testPathsRunFromTheFountainToEveryDistrict() {
        for seed in UInt64(1)...5 {
            let t = Terrain(seed: seed), rects = World.layout(seed: seed)
            XCTAssertEqual(t.paths.count, 6)
            for (k, path) in t.paths.enumerated() {
                XCTAssertEqual(path.first, rects[0].center)
                XCTAssertEqual(path.last, rects[k + 1].center)
                for s in stride(from: 0.0, through: 1.0, by: 0.01) {
                    XCTAssertEqual(t.at(path[0] + (path[1] - path[0]) * s), .path)
                }
            }
        }
    }

    func testBlobsHaveNoSpecks() {
        for seed in UInt64(1)...5 {
            let t = Terrain(seed: seed), n = Terrain.blob
            func at(_ c: Int, _ r: Int) -> Terrain.Cell? { c >= 0 && r >= 0 && c < t.cols && r < t.rows ? t.cells[r * t.cols + c] : nil }
            for r in 0..<t.rows {
                for c in 0..<t.cols where !t.cells[r * t.cols + c].walkable {
                    let kind = t.cells[r * t.cols + c]
                    // Some 4×4 block around it is all this obstacle, or a path cut through it.
                    let covered = (0..<n).contains { dr in (0..<n).contains { dc in
                        (0..<n).allSatisfy { y in (0..<n).allSatisfy { x in
                            let o = at(c - dc + x, r - dr + y)
                            return o == kind || o == .path
                        } }
                    } }
                    XCTAssertTrue(covered, "speck at \(c), \(r)")
                }
            }
        }
    }

    func testNobodyEndsInWaterOrRock() {
        var w = world(seed: 5, count: 60)
        XCTAssertGreaterThanOrEqual(w.districts.count, 5)
        let t = w.terrain
        func check(_ when: String) {
            for b in w.bichitos where b.mood != .held { XCTAssertTrue(t.walkable(b.pos), "\(b.name) in \(t.at(b.pos)) \(when)") }
            for e in w.eggs { XCTAssertTrue(t.walkable(e.pos), "egg \(when)") }
            for f in w.foods { XCTAssertTrue(t.walkable(f.pos), "food \(when)") }
        }
        check("after spawning")
        w.visibleRect = w.bounds
        // Thrown hard, some of them dropped right over the water and rocks.
        let obstacles = w.districts.flatMap { d in
            stride(from: d.rect.x, to: d.rect.x + d.rect.w, by: 40).flatMap { x in
                stride(from: d.rect.y, to: d.rect.y + d.rect.h, by: 40).map { Vec(x, $0) }
            }
        }.filter { !t.walkable($0) }
        XCTAssertFalse(obstacles.isEmpty)
        for (k, b) in w.bichitos.enumerated() where k % 3 == 0 {
            w.grab(b.id)
            w.move(b.id, to: obstacles[k % obstacles.count])
            w.release(b.id, velocity: Vec(k % 2 == 0 ? 3000 : -2000, -2500))
        }
        check("after landing")
        for (k, p) in obstacles.enumerated() where k % 7 == 0 { w.dropFood(at: p) }
        check("after dropping food")
        for k in 0..<4000 {
            if k == 2000 { w.visibleRect = nil }
            w.tick()
            if k % 50 == 0 { check("at tick \(k)") }
        }
        check("after 4000 ticks")
        w.catchUp(seconds: 3 * 3600)
        check("after a catch-up")
    }

    func testSpawnsAndFoodDropsAreWalkable() {
        var w = world(seed: 8, count: 98) // every district open
        let t = w.terrain
        XCTAssertTrue(w.bichitos.allSatisfy { t.walkable($0.pos) })
        let m = w.bounds
        for x in stride(from: m.x, to: m.x + m.w, by: 52) {
            for y in stride(from: m.y, to: m.y + m.h, by: 52) {
                let id = w.dropFood(at: Vec(x, y))
                XCTAssertTrue(t.walkable(w.foods.first { $0.id == id }!.pos))
            }
        }
        XCTAssertTrue(w.foods.allSatisfy { m.contains($0.pos) })
    }

    func testTerrainIsNotSaved() throws {
        let w = world(seed: 5, count: 30)
        let json = String(decoding: try JSONEncoder().encode(w), as: UTF8.self)
        XCTAssertFalse(json.contains("terrain") || json.contains("cells"))
        let back = try JSONDecoder().decode(World.self, from: Data(json.utf8))
        XCTAssertEqual(back.terrain.cells, w.terrain.cells)
    }
}

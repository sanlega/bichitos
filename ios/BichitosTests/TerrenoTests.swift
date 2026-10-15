import XCTest
import UIKit
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

    // MARK: - Painting (#36)

    /// A `cols` × `rows` mask, true inside the cells `inside` says.
    private func mask(_ cols: Int, _ rows: Int, _ inside: (Int, Int) -> Bool?) -> [Bool?] {
        (0..<rows).flatMap { r in (0..<cols).map { c in inside(c, r) } }
    }

    /// Even-odd: inside an odd number of loops.
    private func inside(_ p: Vec, _ loops: [[Vec]]) -> Bool {
        var odd = false
        for l in loops {
            for (a, b) in zip(l, l.dropFirst() + [l[0]]) where (a.y > p.y) != (b.y > p.y) {
                if p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x) { odd.toggle() }
            }
        }
        return odd
    }

    func testALoneBlobIsACircleOf16u() {
        let loops = Terrain.outlines(mask(12, 12) { (4...7).contains($0) && (4...7).contains($1) }, cols: 12, rows: 12, origin: .zero)
        XCTAssertEqual(loops.count, 1)
        let d = loops[0].map { ($0 - Vec(96, 96)).length }
        print("OUTLINE 4×4 blob: \(loops[0].count) points, radius \(d.min()!)...\(d.max()!)")
        XCTAssertGreaterThan(loops[0].count, 8)
        XCTAssertTrue(d.allSatisfy { (26...38).contains($0) }, "\(d)") // 16 u = 32 world units
    }

    func testStraightRunsStayOnTheCellEdgesAndCornersRoundOff() {
        let loops = Terrain.outlines(mask(16, 16) { (3...12).contains($0) && (3...12).contains($1) }, cols: 16, rows: 16, origin: .zero)
        XCTAssertEqual(loops.count, 1)
        for p in loops[0] where abs(p.x - 128) < 32 { XCTAssertTrue(abs(p.y - 48) < 1 || abs(p.y - 208) < 1, "\(p)") }
        for p in loops[0] where abs(p.y - 128) < 32 { XCTAssertTrue(abs(p.x - 48) < 1 || abs(p.x - 208) < 1, "\(p)") }
        for corner in [Vec(48, 48), Vec(208, 48), Vec(48, 208), Vec(208, 208)] {
            XCTAssertGreaterThan(loops[0].map { ($0 - corner).length }.min()!, 8)
        }
        XCTAssertTrue(inside(Vec(128, 128), loops))
        XCTAssertFalse(inside(Vec(20, 20), loops))
    }

    func testSpecksVanishAndUnknownCellsTakeTheirNeighbours() {
        XCTAssertTrue(Terrain.outlines(mask(8, 8) { (3...4).contains($0) && (3...4).contains($1) }, cols: 8, rows: 8, origin: .zero).isEmpty)
        XCTAssertTrue(Terrain.outlines(mask(8, 8) { _, _ in false }, cols: 8, rows: 8, origin: .zero).isEmpty)
        XCTAssertEqual(Terrain.outlines(mask(9, 9) { (3...5).contains($0) && (3...5).contains($1) }, cols: 9, rows: 9, origin: .zero).count, 1)
        // A 3-cell gap through a blob: cut when it is known ground, bridged when it is unknown (a path over the pond).
        func blob(gap: Bool?) -> [[Vec]] {
            Terrain.outlines(mask(20, 12) { c, r in (2...9).contains(r) && (2...17).contains(c) ? ((8...10).contains(c) ? gap : true) : false },
                             cols: 20, rows: 12, origin: Vec(-100, 50))
        }
        XCTAssertEqual(blob(gap: false).count, 2)
        XCTAssertEqual(blob(gap: nil).count, 1)
        XCTAssertTrue(inside(Vec(-100 + 9.5 * 16, 50 + 6 * 16), blob(gap: nil)))
    }

    func testOutlinesFollowTheCells() {
        for seed in UInt64(1)...5 {
            let t = Terrain(seed: seed), rects = World.layout(seed: seed)
            for (k, rect) in rects.enumerated() {
                let look = Terrain.look(District.themes[k].terrain)
                for kind in [look.other] + (look.obstacle.map { [$0] } ?? []) {
                    let loops = t.outlines(kind, in: rect, under: kind == look.other ? [.rock, .water] : [])
                    XCTAssertTrue(loops.allSatisfy { $0.count >= 3 })
                    func around(_ p: Vec, _ n: Int) -> [Terrain.Cell] {
                        (-n...n).flatMap { dy in (-n...n).map { dx in t.at(p + Vec(Double(dx), Double(dy)) * Terrain.cell) } }
                    }
                    for y in stride(from: rect.y + 8, to: rect.y + rect.h, by: Terrain.cell) {
                        for x in stride(from: rect.x + 8, to: rect.x + rect.w, by: Terrain.cell) {
                            let p = Vec(x, y), near = around(p, 2)
                            if around(p, 1).allSatisfy({ $0 == kind }) { XCTAssertTrue(inside(p, loops), "\(kind) at \(p), seed \(seed)") }
                            if !near.contains(kind) && !near.contains(.path) && (kind != look.other || !near.contains { !$0.walkable }) {
                                XCTAssertFalse(inside(p, loops), "no \(kind) at \(p), seed \(seed)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testGroundIsPaintedOncePerDistrictAndZoomLevel() {
        let key = { (d: Int, open: [Int], level: Camera.Level) in Ground.Key(seed: 7, district: d, open: open, texel: Ground.texel(level)) }
        XCTAssertEqual(key(0, [0], .district), key(0, [0], .district))
        XCTAssertNotEqual(key(0, [0], .district), key(1, [0], .district))
        XCTAssertNotEqual(key(0, [0], .district), key(0, [0, 3], .district), "a new district brings a new path")
        XCTAssertNotEqual(key(0, [0], .district), key(0, [0], .street))
        XCTAssertEqual(key(0, [0], .street), key(0, [0], .close), "capped: Calle and Cerca share one texture")
        XCTAssertEqual(Set([key(0, [0], .district), key(0, [0], .district), key(0, [0], .street)]).count, 2)
        XCTAssertEqual(Ground.texel(.district), 1.5) // one texture pixel per screen point
        XCTAssertLessThanOrEqual(Ground.frame(World.layout(seed: 7)[0]).w * Ground.texel(.close), 2048)
    }

    func testEveryPathIsInsidePaintedGround() {
        for seed in UInt64(1)...5 {
            let t = Terrain(seed: seed), frames = World.layout(seed: seed).map(Ground.frame)
            for (k, path) in t.paths.enumerated() {
                for s in stride(from: 0.0, through: 1.0, by: 0.01) {
                    let p = path[0] + (path[1] - path[0]) * s
                    XCTAssertTrue(frames[0].contains(p) || frames[k + 1].contains(p), "path \(k) at \(p), seed \(seed)")
                }
            }
            for (a, b) in zip(frames, frames.dropFirst()) { XCTAssertEqual(a.w, b.w) }
        }
    }

    /// Writes every district's painted ground (seed 7, all open) to `GALLERY_DIR`, to review water and rock by eye.
    func testWriteGround() throws {
        guard let dir = ProcessInfo.processInfo.environment["GALLERY_DIR"], !dir.isEmpty else { throw XCTSkip("GALLERY_DIR not set") }
        let t = Terrain(seed: 7)
        for d in District.themes.indices {
            let texture = Ground.paint(Ground.Key(seed: 7, district: d, open: [0, d], texel: Ground.texel(.district)), t)
            let png = try XCTUnwrap(UIImage(cgImage: texture.cgImage()).pngData())
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ground-\(d).png"))
        }
    }
}

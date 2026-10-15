import XCTest
@testable import Bichitos

final class MaquetaTests: XCTestCase {
    let buildings = Terrain(seed: 5).buildings

    func testRecipesAreDeterministicFromTheSeed() {
        for b in buildings { XCTAssertEqual(Maqueta.shapes(b), Maqueta.shapes(b), "\(b.kind)") }
        // Another seed, another casita: roof, door, windows, extra or lightness change.
        let casitas = buildings.filter { $0.kind == .casita }
        XCTAssertTrue(casitas.contains { Maqueta.shapes($0) != Maqueta.shapes(casitas[0]) })
        let other = Building(id: casitas[0].id, kind: .casita, theme: casitas[0].theme, rect: casitas[0].rect, base: casitas[0].base,
                             blocks: casitas[0].blocks, door: casitas[0].door, seed: casitas[0].seed &+ 1)
        XCTAssertEqual(Maqueta.shapes(other), Maqueta.shapes(other))
    }

    /// Every kind and every district's monument draws something, inside its texture, with no stroke under 2 u (4 world units).
    func testEveryKindDrawsInsideItsFrame() {
        XCTAssertEqual(Set(buildings.map(\.kind.rawValue)), Set(Building.Kind.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(buildings.filter { $0.kind == .monument }.map(\.theme)), Set(District.themes.indices))
        for b in buildings {
            let shapes = Maqueta.shapes(b, closed: true, lit: true)
            XCTAssertFalse(shapes.isEmpty, "\(b.kind)")
            let p = Maqueta.pad
            func inside(_ v: Vec) -> Bool { v.x >= -p && v.y >= -p && v.x <= b.rect.w + p && v.y <= b.rect.h + p }
            for s in shapes {
                switch s.form {
                case let .box(r, _), let .oval(r), let .arch(r), let .ring(r, _):
                    XCTAssertTrue(inside(Vec(r.x, r.y)) && inside(Vec(r.x + r.w, r.y + r.h)), "\(b.kind) \(s.form)")
                case let .poly(v, _):
                    XCTAssertTrue(v.allSatisfy(inside), "\(b.kind) \(s.form)")
                case let .line(v, width):
                    XCTAssertTrue(v.allSatisfy(inside), "\(b.kind) \(s.form)")
                    XCTAssertGreaterThanOrEqual(width, 4, "\(b.kind)")
                }
            }
        }
    }

    func testOccupiedShutsTheDoorAndNightLightsTheWindows() {
        let casita = buildings.first { $0.kind == .casita }!, tree = buildings.first { $0.kind == .tree }!
        XCTAssertNotEqual(Maqueta.shapes(casita, closed: true), Maqueta.shapes(casita))
        XCTAssertNotEqual(Maqueta.shapes(casita, lit: true), Maqueta.shapes(casita))
        XCTAssertEqual(Maqueta.shapes(tree, closed: true), Maqueta.shapes(tree))
    }

    func testTextureKeyIsOnePerBuildingStateAndZoomLevel() {
        let casita = buildings.first { $0.kind == .casita }!, tree = buildings.first { $0.kind == .tree }!
        XCTAssertEqual(Maqueta.key(casita, level: .district), Maqueta.key(casita, level: .district))
        XCTAssertNotEqual(Maqueta.key(casita, level: .district), Maqueta.key(casita, level: .street))
        XCTAssertNotEqual(Maqueta.key(casita, level: .district), Maqueta.key(tree, level: .district))
        XCTAssertNotEqual(Maqueta.key(casita, closed: true, level: .district), Maqueta.key(casita, level: .district))
        XCTAssertNotEqual(Maqueta.key(casita, lit: true, level: .district), Maqueta.key(casita, level: .district))
        // Only casitas have a door to shut, and Cerca reuses Calle's texture (capped texel).
        XCTAssertEqual(Maqueta.key(tree, closed: true, level: .district), Maqueta.key(tree, level: .district))
        XCTAssertEqual(Maqueta.key(casita, level: .street), Maqueta.key(casita, level: .close))
        XCTAssertLessThanOrEqual(Maqueta.texel(.close), 6)
    }

    /// Lower on screen covers what is above: a bichito with its feet behind a casita's base hides behind it.
    func testYSortPutsWhatIsLowerOnScreenOnTop() {
        let casita = buildings.first { $0.kind == .casita }!, nido = buildings.first { $0.kind == .nido }!
        func z(_ y: Double) -> Double { Maqueta.depth(y, top: casita.rect.y - 300, unit: 1.5) }
        let base = Maqueta.sortY(casita)
        XCTAssertEqual(base, casita.rect.y + casita.rect.h)
        XCTAssertLessThan(z(Maqueta.feet(Vec(0, base - 30), radius: 12)), z(base)) // behind
        XCTAssertGreaterThan(z(Maqueta.feet(casita.door!, radius: 12)), z(base))   // at the door, in front
        // A bowl sorts by its middle, so the eggs in it are drawn over its back rim.
        XCTAssertGreaterThan(z(nido.rect.y + nido.rect.h * 0.75), z(Maqueta.sortY(nido)))
        XCTAssertLessThan(Maqueta.sortY(nido), nido.rect.y + nido.rect.h)
    }

    func testOnlyOwnersAsleepAtTheDoorAreInside() {
        var w = World(seed: 3, date: Date(timeIntervalSince1970: 1_700_000_000))
        var rng = SeededRNG(seed: 3)
        let id = w.add(Recipe.random(using: &rng))
        let i = w.index(of: id)!
        guard let home = w.bichitos[i].home, let door = w.building(home)?.door else { return XCTFail("no casita") }
        w.bichitos[i].pos = door
        w.bichitos[i].enter(.sleep, for: 60)
        XCTAssertEqual(w.asleepInside, [home: [id]])
        w.bichitos[i].enter(.wander, for: 60)
        XCTAssertEqual(w.asleepInside, [:])
        w.bichitos[i].enter(.sleep, for: 60)
        w.bichitos[i].pos = door + Vec(0, 80)
        XCTAssertEqual(w.asleepInside, [:])
        // Left at its door with the sim running, it stays inside until rested.
        w.bichitos[i].pos = door
        w.bichitos[i].needs.sleep = 0.1
        w.bichitos[i].enter(.sleep, for: 600)
        w.visibleRect = Rect(x: door.x - 200, y: door.y - 300, w: 400, h: 600)
        for _ in 0..<200 { w.tick() }
        XCTAssertEqual(w.bichitos[w.index(of: id)!].mood, .sleep)
        XCTAssertEqual(w.asleepInside, [home: [id]], "pos \(w.bichitos[w.index(of: id)!].pos) door \(door)")
    }
}

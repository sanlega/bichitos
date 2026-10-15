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
        var w = World(seed: 2, date: Date(timeIntervalSince1970: 1_700_000_000))
        var rng = SeededRNG(seed: 2)
        for _ in 0..<110 { w.add(Recipe.random(using: &rng)) }
        XCTAssertEqual(w.districts.count, 7)
    }

    /// A save from before design v2: 8 districts, with bichitos, a note and events in the 8th one.
    func testOldEightDistrictSaveLoadsWithEveryone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pen = Pen(url: dir.appendingPathComponent("pen.json"))
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        var w = World(seed: 9, date: start)
        var rng = SeededRNG(seed: 9)
        for _ in 0..<20 { w.add(Recipe.random(using: &rng)) }
        try pen.save(w, at: start)

        // Rewrite it into the old shape.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pen.url)) as? [String: Any])
        var world = try XCTUnwrap(json["world"] as? [String: Any])
        world["districts"] = (0..<8).map { ["index": $0] }
        var bichitos = try XCTUnwrap(world["bichitos"] as? [[String: Any]])
        for i in 0..<3 {
            bichitos[i]["district"] = 7
            bichitos[i]["pos"] = ["x": 7500.0, "y": 800.0]
        }
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
        for b in loaded.bichitos + loaded.notes.map(\.bichito) {
            XCTAssertLessThan(b.district, 7)
            XCTAssertLessThanOrEqual(b.pos.x, loaded.size.x)
        }
        XCTAssertLessThanOrEqual(loaded.notes[0].pos.x, loaded.size.x)
        XCTAssertTrue(loaded.events.isEmpty)

        let opened = try XCTUnwrap(pen.open(now: start + 600).world, "fast-forward and summary don't trip on it")
        XCTAssertGreaterThanOrEqual(opened.bichitos.count + opened.notes.count, 20) // a pair may breed meanwhile
    }
}

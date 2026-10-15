import XCTest
@testable import Bichitos

final class RelationsTests: XCTestCase {
    private func world(_ count: Int) -> World {
        var w = World(seed: 2)
        var rng = SeededRNG(seed: 2)
        for _ in 0..<count { w.add(Recipe.random(using: &rng)) }
        return w
    }

    func testFriendsAndRivalsRankedByFeeling() {
        var w = world(7)
        let ids = w.bichitos.map { $0.id }
        let me = w.index(of: ids[0])!
        w.bichitos[me].affinity = [ids[1]: 0.3, ids[2]: 0.9, ids[3]: 0.05, ids[4]: -0.7, ids[5]: -0.2, ids[6]: 0.3]
        XCTAssertEqual(w.friends(of: ids[0]).map(\.id), [ids[2], ids[1], ids[6]]) // tie broken by id
        XCTAssertEqual(w.friends(of: ids[0], limit: 1).map(\.id), [ids[2]])
        XCTAssertEqual(w.rivals(of: ids[0]).map(\.id), [ids[4], ids[5]])
        XCTAssertTrue(w.friends(of: ids[1]).isEmpty)
    }

    func testGoneBichitosAreLeftOut() {
        var w = world(3)
        let ids = w.bichitos.map { $0.id }
        let me = w.index(of: ids[0])!
        w.bichitos[me].affinity = [ids[1]: 0.8, 999: 0.9, ids[2]: -0.5]
        w.bichitos.removeAll { $0.id == ids[2] }
        XCTAssertEqual(w.friends(of: ids[0]).map(\.id), [ids[1]])
        XCTAssertTrue(w.rivals(of: ids[0]).isEmpty)
        XCTAssertTrue(w.friends(of: 12345).isEmpty)
    }

    func testFamily() {
        var w = world(2)
        let ids = w.bichitos.map { $0.id }
        var rng = SeededRNG(seed: 3)
        let child = w.add(Recipe.random(using: &rng), parents: [ids[0], ids[1]])
        XCTAssertEqual(w.parents(of: child).map(\.id), [ids[0], ids[1]])
        XCTAssertEqual(w.children(of: ids[0]).map(\.id), [child])
        XCTAssertTrue(w.parents(of: ids[0]).isEmpty)
    }

    func testRename() {
        var w = world(1)
        let id = w.bichitos[0].id
        let old = w.bichitos[0].name
        w.rename(id, to: "  Zorro ")
        XCTAssertEqual(w.bichitos[0].name, "Zorro")
        XCTAssertTrue(w.bichitos[0].description.hasPrefix("Zorro, "), w.bichitos[0].description)
        XCTAssertFalse(w.bichitos[0].description.contains(old))
        w.rename(id, to: "   ")
        XCTAssertEqual(w.bichitos[0].name, "Zorro")
    }
}

import XCTest
@testable import Bichitos

final class NoticiasTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func pair() -> (World, Int, Int) {
        var w = World(testSeed: 7, date: start)
        var rng = SeededRNG(seed: 7)
        let a = w.add(Recipe.random(using: &rng), at: Vec(100, 100), name: "Chencho")
        let b = w.add(Recipe.random(using: &rng), at: Vec(300, 300), name: "Ramona")
        return (w, a, b)
    }

    func testKeepsTheTwentyNewest() {
        var n = News()
        for i in 1...25 { n.add(.hatched(i), date: start + Double(i), place: .zero) }
        XCTAssertEqual(n.items.count, 20)
        XCTAssertEqual(n.items.first?.event, .hatched(25))
        XCTAssertEqual(n.items.last?.event, .hatched(6))
    }

    func testRepeatsAreGrouped() {
        var (w, a, b) = pair()
        for k in 0..<14 { w.news.add(k % 2 == 0 ? .fought(a, b) : .fought(b, a), date: start + Double(k), place: Vec(1, 1)) }
        w.news.add(.fellInLove(a, b), date: start + 100, place: .zero)
        XCTAssertEqual(w.news.items.count, 2)
        XCTAssertEqual(w.news.items[1].count, 14)
        XCTAssertEqual(w.newsText(w.news.items[1], .es), "Chencho y Ramona se pelearon 14 veces.")
        XCTAssertEqual(w.newsText(w.news.items[1], .en), "Chencho and Ramona fought 14 times.")
        XCTAssertEqual(w.newsText(w.news.items[0], .es), "Chencho y Ramona se enamoraron.")

        w.news.add(.fought(b, a), date: start + 200, place: Vec(5, 5))
        let top = w.news.items[0]
        XCTAssertEqual(w.news.items.count, 2)
        XCTAssertEqual(top.count, 15)
        XCTAssertEqual(top.date, start + 200, "date bumped")
        XCTAssertEqual(top.place, Vec(5, 5))
        XCTAssertEqual(top.bichitos, [a, b])
    }

    func testRecordedEventsBecomeNews() {
        var w = World(testSeed: 3, date: start)
        var rng = SeededRNG(seed: 3)
        for _ in 0...World.capacity { w.add(Recipe.random(using: &rng)) } // one too many: opens district 1
        let item = w.news.items.first
        XCTAssertEqual(item?.event, .unlocked(1, w.districts[1].theme.affine))
        XCTAssertEqual(item?.place, w.districts[1].rect.center)
        XCTAssertEqual(item?.bichitos, [])
    }

    func testSurvivesCatchUp() {
        var (w, a, b) = pair()
        w.news.add(.fought(a, b), date: start, place: .zero)
        w.events.append(.fought(a, b))
        w.catchUp(seconds: 60)
        XCTAssertFalse(w.events.contains(.fought(a, b)), "the summary log was cleared")
        XCTAssertTrue(w.news.items.contains { $0.event == .fought(a, b) })
    }

    func testSavedAndOldSavesStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pen = Pen(url: dir.appendingPathComponent("pen.json"), timeZone: World.daytime)

        var (w, a, b) = pair()
        w.news.add(.fought(a, b), date: start, place: Vec(2, 3))
        w.news.add(.fought(a, b), date: start + 5, place: Vec(2, 3))
        try pen.save(w, at: start)
        let loaded = try XCTUnwrap(try pen.load()?.world)
        XCTAssertEqual(loaded.news, w.news)
        XCTAssertEqual(loaded.news.items.first?.count, 2)

        // A save from before the news existed has no "newsLog" key.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pen.url)) as? [String: Any])
        var world = try XCTUnwrap(json["world"] as? [String: Any])
        world["newsLog"] = nil
        json["world"] = world
        try JSONSerialization.data(withJSONObject: json).write(to: pen.url)
        let old = try XCTUnwrap(try pen.load()?.world)
        XCTAssertEqual(old.news.items, [])
        XCTAssertEqual(old.bichitos.map(\.id), w.bichitos.map(\.id))
    }
    func testFeedIsNewestFirst() {
        var n = News()
        n.add(.fought(1, 2), date: start, place: .zero)
        n.add(.hatched(3), date: start + 10, place: .zero)
        n.add(.escaped(4), date: start + 20, place: .zero)
        n.add(.fought(2, 1), date: start + 30, place: .zero) // a repeat jumps back to the top
        XCTAssertEqual(n.items.map(\.event), [.fought(1, 2), .escaped(4), .hatched(3)])
        XCTAssertEqual(n.items.map(\.date), n.items.map(\.date).sorted(by: >))
    }

    func testRelativeTime() {
        func ago(_ s: Double, _ l: Language) -> String { News.ago(start - s, now: start, l) }
        XCTAssertEqual(ago(0, .es), "ahora")
        XCTAssertEqual(ago(59, .en), "just now")
        XCTAssertEqual(ago(-5, .es), "ahora", "a story from the future is just now")
        XCTAssertEqual(ago(180, .es), "hace 3 min")
        XCTAssertEqual(ago(180, .en), "3 min ago")
        XCTAssertEqual(ago(3599, .es), "hace 59 min")
        XCTAssertEqual(ago(7200, .es), "hace 2 h")
        XCTAssertEqual(ago(3 * 86400, .en), "3 d ago")
    }

    func testToastTravelsToItsStory() {
        var n = News()
        n.add(.fellInLove(5, 2), date: start, place: Vec(10, 20))
        n.add(.hatched(7), date: start + 1, place: Vec(30, 40))
        n.add(.fellInLove(2, 5), date: start + 2, place: Vec(50, 60))
        XCTAssertEqual(n.place(of: .fellInLove(5, 2)), Vec(50, 60), "either order, latest place")
        XCTAssertEqual(n.place(of: .hatched(7)), Vec(30, 40))
        XCTAssertNil(n.place(of: .escaped(9)))
    }
}

import XCTest
@testable import Bichitos

final class NocheTests: XCTestCase {
    let utc = TimeZone(secondsFromGMT: 0)!
    let midnight = Date(timeIntervalSince1970: 1_699_920_000) // 14 Nov 2023, 00:00 UTC

    /// 14 bichitos all in Plaza Mayor, 2 per casita.
    private func world(at hour: Double, seed: UInt64 = 4, count: Int = 14) -> World {
        var w = World(seed: seed, date: midnight + hour * 3600)
        w.timeZone = utc
        var rng = SeededRNG(seed: seed)
        for _ in 0..<count { w.add(Recipe.random(using: &rng)) }
        return w
    }

    private func asleep(_ w: World) -> [Bichito] { w.bichitos.filter { $0.mood == .sleep } }

    private func atTheirDoor(_ w: World, _ list: [Bichito]) -> Int {
        let t = w.terrain
        return list.filter { b in b.home.flatMap { t.buildings[$0].door }.map { (b.pos - $0).length < 48 } ?? false }.count
    }

    func testPhasesFollowTheLocalClock() {
        let cases: [(Double, DayPhase)] = [(0, .night), (5.99, .night), (6, .dawn), (7.99, .dawn), (8, .day), (18.99, .day),
                                           (19, .dusk), (20.99, .dusk), (21, .night), (23.99, .night)]
        for (h, p) in cases { XCTAssertEqual(DayPhase(hour: h), p, "at \(h)") }
        XCTAssertEqual(DayPhase.drowsiness(hour: 12), 0)
        XCTAssertEqual(DayPhase.drowsiness(hour: 20), 0.5, accuracy: 1e-9)
        XCTAssertEqual(DayPhase.drowsiness(hour: 2), 1)
        XCTAssertEqual(DayPhase.drowsiness(hour: 7), 0.5, accuracy: 1e-9)

        var w = world(at: 22, count: 0)
        XCTAssertEqual(w.phase, .night)
        w.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        XCTAssertEqual(w.phase, .dawn)
        w.timeZone = TimeZone(secondsFromGMT: -10 * 3600)!
        XCTAssertEqual(w.phase, .day)
        XCTAssertEqual(w.hour, 12, accuracy: 1e-6)
    }

    func testMoreSleepAtNightAndInTheirCasitas() {
        var day = world(at: 12), night = world(at: 23)
        for _ in 0..<4000 { day.tick(); night.tick() } // 200 s: past the 90 s a walk to bed may take
        let d = asleep(day).count, n = asleep(night), home = atTheirDoor(night, n)
        print("NIGHT: \(d) of 14 asleep at 12:00, \(n.count) at 23:00, \(home) of them at their door")
        XCTAssertGreaterThan(n.count, d)
        XCTAssertGreaterThanOrEqual(n.count, 11)
        XCTAssertGreaterThanOrEqual(home * 4, n.count * 3, "mostly in bed")
        XCTAssertTrue(night.terrain.buildings.contains { $0.kind == .casita && night.windowLit($0.id) })
        XCTAssertFalse(day.terrain.buildings.contains { $0.kind == .casita && day.windowLit($0.id) })
    }

    func testCatchUpAcrossTheNight() {
        // Left at 20:00 for 6 h: needs only until 00:00, then the full simulation until 02:00.
        var night = world(at: 20)
        night.bichitos[0].needs.sleep = 0.2
        night.catchUp(seconds: 6 * 3600)
        XCTAssertEqual(night.phase, .night)
        XCTAssertEqual(night.date.timeIntervalSince(midnight), 26 * 3600, accuracy: 1)
        let n = asleep(night)
        XCTAssertGreaterThanOrEqual(n.count, 11)
        XCTAssertGreaterThanOrEqual(atTheirDoor(night, n) * 4, n.count * 3)
        XCTAssertGreaterThan(night.bichitos[0].needs.sleep, 0.9, "rested overnight")

        // Left at 20:00 for 14 h: they slept through the night in the needs-only part and woke at dawn.
        var morning = world(at: 20)
        morning.catchUp(seconds: 14 * 3600)
        XCTAssertEqual(morning.phase, .day)
        let m = asleep(morning).count
        print("CATCHUP NIGHT: \(n.count) of 14 asleep at 02:00, \(m) at 10:00")
        XCTAssertLessThan(m * 2, morning.bichitos.count)
        XCTAssertTrue(morning.bichitos.allSatisfy { $0.needs.sleep > 0.3 })
    }
}

import XCTest
@testable import Bichitos

final class ToastTests: XCTestCase {
    func testOneAtATimeForThreeSeconds() {
        var t = Toasts()
        t.push(.eggLaid(1, 2), at: 0)
        t.push(.hatched(3), at: 0)
        t.update(at: 0)
        XCTAssertEqual(t.current, .eggLaid(1, 2))
        t.update(at: 2.9)
        XCTAssertEqual(t.current, .eggLaid(1, 2), "nothing steps on the toast on screen")
        t.update(at: 3)
        XCTAssertEqual(t.current, .hatched(3))
        t.update(at: 6)
        XCTAssertNil(t.current)
    }

    func testFloodOfTheSameKindAndPairIsDropped() {
        var t = Toasts()
        t.push(.fellInLove(1, 2), at: 0)
        t.push(.fellInLove(2, 1), at: 1)
        t.push(.fellInLove(1, 2), at: 5)
        t.push(.fellInLove(1, 3), at: 5) // another pair is news
        t.update(at: 5)
        t.update(at: 8)
        XCTAssertEqual(t.current, .fellInLove(1, 3))
        t.update(at: 11)
        XCTAssertNil(t.current)
        t.push(.fellInLove(1, 2), at: 5 + Toasts.window)
        t.update(at: 5 + Toasts.window)
        XCTAssertEqual(t.current, .fellInLove(1, 2), "after the window the same pair can show again")
    }

    func testQueueNeverPilesUpAndFightsAreIgnored() {
        var t = Toasts()
        t.push(.fought(1, 2), at: 0)
        for id in 1...10 { t.push(.hatched(id), at: 0) }
        var shown: [WorldEvent] = []
        for k in 0...20 {
            t.update(at: Double(k) * 3)
            if let c = t.current { shown.append(c) }
        }
        XCTAssertEqual(shown, [.hatched(1), .hatched(2), .hatched(3)])
    }

    func testLiveEventsAdvanceTheCursorAndHaveText() {
        var w = World(seed: 1, date: Date(timeIntervalSince1970: 1_700_000_000))
        var rng = SeededRNG(seed: 1)
        let a = w.add(Recipe.random(using: &rng)), b = w.add(Recipe.random(using: &rng))
        let before = w.eventTotal
        w.record(.eggLaid(a, b))
        XCTAssertEqual(w.eventTotal, before + 1)
        XCTAssertEqual(w.toastText(.eggLaid(a, b)), "\(w.bichito(a)!.name) y \(w.bichito(b)!.name) pusieron un huevo.")
    }
}

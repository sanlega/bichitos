import XCTest
@testable import Bichitos

final class GestureTests: XCTestCase {
    func testStillFingerIsATap() {
        var t = Touch(at: Vec(100, 100), time: 0, target: 7, foodMode: false)
        XCTAssertEqual(t.move(to: Vec(104, 103), time: 0.05), .none, "a little wobble is still a tap")
        XCTAssertFalse(t.isDrag)
        XCTAssertEqual(t.tapAction, .peek(7), "a tap opens the peek, it no longer pets")
    }

    func testDragGrabsOnceAndIsNotATap() {
        var t = Touch(at: Vec(100, 100), time: 0, target: 7, foodMode: true)
        XCTAssertEqual(t.move(to: Vec(100, 115), time: 0.02), .grab(7))
        XCTAssertEqual(t.move(to: Vec(100, 140), time: 0.04), .none, "grabs only when the drag starts")
        XCTAssertTrue(t.isDrag)
        XCTAssertEqual(t.tapAction, .none)
    }

    func testGroundTapFeedsInFoodModeAndOtherwiseClosesThePeek() {
        XCTAssertEqual(Touch(at: .zero, time: 0, target: nil, foodMode: true).tapAction, .feed)
        XCTAssertEqual(Touch(at: .zero, time: 0, target: nil, foodMode: false).tapAction, .close)
        XCTAssertEqual(Touch(at: .zero, time: 0, target: 3, foodMode: true).tapAction, .peek(3), "a bichito under the finger wins")
        var drag = Touch(at: .zero, time: 0, target: nil, foodMode: true)
        XCTAssertEqual(drag.move(to: Vec(50, 0), time: 0.1), .pan, "dragging the ground pans")
        XCTAssertEqual(drag.tapAction, .none)
    }

    /// Feeds a path of x positions (y fixed) one sample every `dt`; returns every action that came out.
    private func run(_ t: inout Touch, _ xs: [Double], dt: Double = 0.03) -> [Touch.Action] {
        xs.enumerated().map { k, x in t.move(to: Vec(100 + x, 100), time: Double(k + 1) * dt) }.filter { $0 != .none }
    }

    func testRubbingBackAndForthPetsAndNeverGrabs() {
        var t = Touch(at: Vec(100, 100), time: 0, target: 4, foodMode: false, reach: 40)
        let strokes: [Double] = [8, 16, 24, 16, 8, 0, -8, 0, 8, 16, 24, 16, 8, 0, -8, 0, 8, 16, 24, 16, 8, 0, -8, 0]
        let actions = run(&t, strokes)
        XCTAssertTrue(t.isRub)
        XCTAssertFalse(t.isDrag)
        XCTAssertGreaterThan(actions.count, 1, "repeated pets while rubbing")
        XCTAssertTrue(actions.allSatisfy { $0 == .rub(4) }, "\(actions)")
        XCTAssertEqual(t.move(to: Vec(200, 100), time: 1), .none, "a rub leaving the bichito doesn't turn into a grab")
        XCTAssertEqual(t.tapAction, .none, "a rub is not a tap")
    }

    func testOneWayDragOnABichitoGrabsOnceItLeavesItsReach() {
        var t = Touch(at: Vec(100, 100), time: 0, target: 4, foodMode: false, reach: 40)
        XCTAssertEqual(run(&t, [10, 20, 30, 40, 50, 60]), [.grab(4)])
        XCTAssertFalse(t.isRub)
        XCTAssertTrue(t.isDrag)
    }

    func testSlowOrJitteryBackAndForthIsNotARub() {
        var jitter = Touch(at: Vec(100, 100), time: 0, target: 4, foodMode: false, reach: 40)
        XCTAssertEqual(run(&jitter, [3, -3, 3, -3, 3, -3, 3]), [], "strokes under rubStroke are jitter")
        XCTAssertFalse(jitter.isRub)
        var slow = Touch(at: Vec(100, 100), time: 0, target: 4, foodMode: false, reach: 40)
        XCTAssertEqual(run(&slow, [20, 0, 20], dt: 1), [], "reversals further apart than rubWindow")
        XCTAssertFalse(slow.isRub)
        XCTAssertEqual(slow.tapAction, .none, "it moved, so lifting isn't a tap either")
    }

    func testTossStaysOnTheMap() {
        var w = World(seed: 5)
        var rng = SeededRNG(seed: 5)
        let corner = Vec(w.bounds.x + 20, w.bounds.y + 20)
        let ids = (0..<6).map { _ in w.add(Recipe.random(using: &rng), at: corner) }
        w.visibleRect = w.bounds
        for _ in 0..<5 {
            for id in ids { w.toss(id, using: &rng) }
            XCTAssertTrue(ids.allSatisfy { (w.bichito($0)?.dizzy ?? 0) > 2 }, "a toss is a real throw")
            for _ in 0..<60 { w.tick() }
            for b in w.bichitos { XCTAssertTrue(w.bounds.contains(b.pos), "\(b.pos) left \(w.bounds)") }
        }
    }

    func testVoiceLabelSaysNameAndState() {
        var w = World(seed: 6)
        var rng = SeededRNG(seed: 6)
        let id = w.add(Recipe.random(using: &rng), at: Vec(300, 300), name: "Pocholo")
        var b = try! XCTUnwrap(w.bichito(id))
        b.mood = .sleep
        b.dizzy = 0
        b.needs = .init(hunger: 0.1, sleep: 1, affection: 1)
        XCTAssertEqual(b.voiceLabel, "Pocholo, durmiendo, con hambre")
    }

    func testFollowHoldsUntilThePanAndStopsWhenItIsGone() {
        var w = World(seed: 3)
        var rng = SeededRNG(seed: 3)
        let id = w.add(Recipe.random(using: &rng), at: Vec(300, 400))
        var f = Follow()
        XCTAssertNil(f.target(in: w))
        f.start(id)
        XCTAssertEqual(f.target(in: w), w.bichito(id)?.pos)
        for action in [Touch.Action.grab(id), .peek(id), .close, .none] { f.after(action) }
        XCTAssertEqual(f.id, id, "grabbing or tapping keeps following")
        f.after(.pan)
        XCTAssertNil(f.id, "a pan hands the camera back")
        XCTAssertNil(f.target(in: w))
        f.start(id)
        w.bichitos.removeAll()
        XCTAssertNil(f.target(in: w))
        XCTAssertNil(f.id, "it ran away: following stops for good")
    }

    func testThrowVelocityComesFromTheLastMotion() {
        var t = Touch(at: Vec(0, 0), time: 0, target: 1, foodMode: false)
        for k in 1...10 { _ = t.move(to: Vec(Double(k) * 20, 0), time: Double(k) * 0.01) }
        let v = t.velocity(at: 0.1)
        XCTAssertEqual(v.x, 2000, accuracy: 1)
        XCTAssertEqual(v.y, 0, accuracy: 1e-9)
        XCTAssertEqual(t.velocity(at: 0.5), .zero, "stopping before lifting drops it gently")
    }

    func testHitPicksTheClosestBody() {
        var w = World(seed: 1)
        var rng = SeededRNG(seed: 1)
        let a = w.add(Recipe.random(using: &rng), at: Vec(200, 200))
        let b = w.add(Recipe.random(using: &rng), at: Vec(240, 200))
        XCTAssertEqual(w.bichito(at: Vec(205, 200), pad: 10), a)
        XCTAssertEqual(w.bichito(at: Vec(236, 202), pad: 10), b)
        XCTAssertNil(w.bichito(at: Vec(600, 600), pad: 10))
    }

    func testThrownBichitoGetsDizzyAndSlowsDown() {
        var w = World(seed: 2)
        var rng = SeededRNG(seed: 2)
        let id = w.add(Recipe.random(using: &rng), at: Vec(500, 300))
        w.visibleRect = w.bounds
        w.grab(id)
        w.move(id, to: Vec(400, 250))
        XCTAssertEqual(w.bichito(id)?.pos, Vec(400, 250))
        w.release(id, velocity: Vec(900, 0))
        XCTAssertGreaterThan(w.bichito(id)?.dizzy ?? 0, 2)
        for _ in 0..<20 { w.tick() }
        let b = try! XCTUnwrap(w.bichito(id))
        XCTAssertGreaterThan(b.pos.x, 450)
        XCTAssertLessThan(b.vel.length, 900)
    }
}

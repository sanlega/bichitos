import XCTest
@testable import Bichitos

final class GestureTests: XCTestCase {
    func testStillFingerIsATap() {
        var t = Touch(at: Vec(100, 100), time: 0, target: 7, foodMode: false)
        XCTAssertEqual(t.move(to: Vec(104, 103), time: 0.05), .none, "a little wobble is still a tap")
        XCTAssertFalse(t.isDrag)
        XCTAssertEqual(t.tapAction, .pet(7))
    }

    func testDragGrabsOnceAndIsNotATap() {
        var t = Touch(at: Vec(100, 100), time: 0, target: 7, foodMode: true)
        XCTAssertEqual(t.move(to: Vec(100, 115), time: 0.02), .grab(7))
        XCTAssertEqual(t.move(to: Vec(100, 140), time: 0.04), .none, "grabs only when the drag starts")
        XCTAssertTrue(t.isDrag)
        XCTAssertEqual(t.tapAction, .none)
    }

    func testGroundTapFeedsOnlyInFoodMode() {
        XCTAssertEqual(Touch(at: .zero, time: 0, target: nil, foodMode: true).tapAction, .feed)
        XCTAssertEqual(Touch(at: .zero, time: 0, target: nil, foodMode: false).tapAction, .none)
        XCTAssertEqual(Touch(at: .zero, time: 0, target: 3, foodMode: true).tapAction, .pet(3), "a bichito under the finger wins")
        var drag = Touch(at: .zero, time: 0, target: nil, foodMode: true)
        XCTAssertEqual(drag.move(to: Vec(50, 0), time: 0.1), .none)
        XCTAssertEqual(drag.tapAction, .none)
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
        let id = w.add(Recipe.random(using: &rng), at: Vec(500, 800))
        w.visibleRect = Rect(x: 0, y: 0, w: 1000, h: 1600)
        w.grab(id)
        w.move(id, to: Vec(400, 700))
        XCTAssertEqual(w.bichito(id)?.pos, Vec(400, 700))
        w.release(id, velocity: Vec(900, 0))
        XCTAssertGreaterThan(w.bichito(id)?.dizzy ?? 0, 2)
        for _ in 0..<20 { w.tick() }
        let b = try! XCTUnwrap(w.bichito(id))
        XCTAssertGreaterThan(b.pos.x, 450)
        XCTAssertLessThan(b.vel.length, 900)
    }
}

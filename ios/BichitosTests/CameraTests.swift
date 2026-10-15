import XCTest
@testable import Bichitos

final class CameraTests: XCTestCase {
    private let screen = Vec(400, 800)

    func testScreenAndWorldMatchAtEveryZoom() {
        for level in Camera.Level.allCases {
            let c = Camera(center: Vec(500, 800), scale: level.scale)
            XCTAssertEqual(c.world(screen * 0.5, screen).x, 500, accuracy: 1e-9)
            XCTAssertEqual(c.world(screen * 0.5, screen).y, 800, accuracy: 1e-9)
            XCTAssertEqual(c.rect(screen).w, 400 / (level.scale / 2), accuracy: 1e-9)
        }
    }

    func testZoomIsContinuousAndKeepsThePointUnderTheFingers() {
        var c = Camera(center: Vec(500, 800), scale: 3)
        let focus = Vec(100, 600)
        let under = c.world(focus, screen)
        c.zoom(to: 4.4, around: focus, screen)
        XCTAssertEqual(c.scale, 4.4)
        XCTAssertEqual(c.world(focus, screen).x, under.x, accuracy: 1e-9)
        XCTAssertEqual(c.world(focus, screen).y, under.y, accuracy: 1e-9)
        c.zoom(to: 20, around: focus, screen)
        XCTAssertEqual(c.scale, 8)
        c.zoom(to: 0.1, around: focus, screen)
        XCTAssertEqual(c.scale, 0.25)
    }

    func testSpritesUseTheNearestWholePixel() {
        XCTAssertEqual(Camera(center: .zero, scale: 1).pixel, 1)
        XCTAssertEqual(Camera(center: .zero, scale: 3.4).pixel, 3)
        XCTAssertEqual(Camera(center: .zero, scale: 3.6).pixel, 4)
        XCTAssertEqual(Camera(center: .zero, scale: 8).pixel, 8)
    }

    func testNearestLevel() {
        XCTAssertEqual(Camera.Level.allCases.map(\.scale), [0.25, 3, 5, 8])
        XCTAssertEqual(Camera.Level.nearest(0.25), .map)
        XCTAssertEqual(Camera.Level.nearest(0.8), .map)
        XCTAssertEqual(Camera.Level.nearest(1), .district) // nearer by ratio, though 1.6 is halfway
        XCTAssertEqual(Camera.Level.nearest(3.8), .district)
        XCTAssertEqual(Camera.Level.nearest(4), .street)
        XCTAssertEqual(Camera.Level.nearest(6.2), .street)
        XCTAssertEqual(Camera.Level.nearest(6.4), .close)
        XCTAssertEqual(Camera(center: .zero, scale: 7).level, .close)
    }

    func testWhatShowsOverTheBichitosPerLevel() {
        XCTAssertEqual(Camera.Level.allCases.map(\.showsIcons), [false, true, true, true])
        XCTAssertEqual(Camera.Level.allCases.map(\.showsWords), [false, false, true, true])
    }

    func testLettingGoSpringsToTheNearestLevelAroundTheFingers() {
        var c = Camera(center: Vec(500, 800), scale: 4.3)
        let focus = Vec(300, 200)
        let under = c.world(focus, screen)
        c.release(around: focus)
        var peak = c.scale, frames = 0
        while c.snap != nil, frames < 600 {
            c.settle(dt: 1.0 / 60, screen)
            peak = max(peak, c.scale)
            frames += 1
        }
        XCTAssertNil(c.snap)
        XCTAssertEqual(c.scale, 5, "lands exactly on Calle")
        XCTAssertGreaterThan(peak, 5, "damping 0.8 overshoots a little")
        XCTAssertLessThan(peak, 5.1)
        XCTAssertLessThan(frames, 90, "settles in well under a second and a half")
        XCTAssertEqual(c.world(focus, screen).x, under.x, accuracy: 1e-9)
        XCTAssertEqual(c.world(focus, screen).y, under.y, accuracy: 1e-9)

        c.zoom(to: 2.5, around: focus, screen)
        c.release(around: focus)
        c.settle(dt: 0.25, screen) // a long frame stays stable
        XCTAssertLessThan(abs(c.scale - 3), 0.5)
        c.grab() // a new pinch takes over
        XCTAssertNil(c.snap)
    }

    func testPanFollowsTheFingerAndStaysOnTheMap() {
        var c = Camera(center: Vec(500, 800), scale: 4) // 2 points per world unit
        c.pan(by: Vec(-100, 40))
        XCTAssertEqual(c.center, Vec(550, 780))
        let map = Rect(x: -1000, y: -400, w: 2000, h: 1600) // the ring reaches left of and above Plaza Mayor
        c.pan(by: Vec(-100_000, 0))
        c.clamp(to: map, screen)
        XCTAssertEqual(c.rect(screen).x + c.rect(screen).w, 1000, accuracy: 1e-9)
        c.pan(by: Vec(0, 100_000))
        c.clamp(to: map, screen)
        XCTAssertEqual(c.rect(screen).y, -400, accuracy: 1e-9)
        var wide = Camera(center: .zero, scale: 3)
        wide.clamp(to: Rect(x: -300, y: 0, w: 200, h: 1600), screen) // map narrower than the screen: centred
        XCTAssertEqual(wide.center.x, -200)
    }

    func testTheWholeRingFitsAtTheMapLevel() {
        let w = World(seed: 3)
        let ring = w.mapBounds
        XCTAssertEqual(ring.center.x, w.districts[0].rect.center.x, accuracy: 1e-9, "Plaza Mayor in the middle")
        XCTAssertEqual(ring.center.y, w.districts[0].rect.center.y, accuracy: 1e-9)
        for phone in [Vec(375, 667), Vec(393, 852), Vec(440, 956)] {
            var c = Camera(center: .zero, scale: 1)
            c.zoom(to: 0, around: phone * 0.5, phone) // pinched all the way out
            XCTAssertEqual(c.level, .map)
            c.clamp(to: ring, phone)
            let r = c.rect(phone)
            XCTAssertLessThanOrEqual(r.x, ring.x)
            XCTAssertLessThanOrEqual(r.y, ring.y)
            XCTAssertGreaterThanOrEqual(r.x + r.w, ring.x + ring.w)
            XCTAssertGreaterThanOrEqual(r.y + r.h, ring.y + ring.h)
        }
    }

    func testDistrictUnderAPoint() {
        var w = World(seed: 1)
        let right = try! XCTUnwrap(w.layout.firstIndex { $0.y == 0 && $0.x > 0 })
        let there = w.layout[right].center, gap = Vec(World.districtSize.x + 10, 100)
        XCTAssertEqual(w.district(at: there), 0, "locked districts don't count")
        w.unlock(right)
        XCTAssertEqual(w.district(at: there), 1)
        XCTAssertEqual(w.district(at: gap), 0, "in the mist, the closest one")
        XCTAssertEqual(w.district(at: Vec(-5, 10)), 0)
    }

    func testMovingOutShowsASuitcase() {
        let fed = Bichito.Needs()
        XCTAssertEqual(Look.bubble(mood: .wander, needs: fed, dizzy: 0, moving: true), "🧳")
        XCTAssertNil(Look.bubble(mood: .wander, needs: fed, dizzy: 0, moving: false))
        XCTAssertEqual(Look.bubble(mood: .sleep, needs: fed, dizzy: 0, moving: true), "💤")
    }
}

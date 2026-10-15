import XCTest
@testable import Bichitos

final class CameraTests: XCTestCase {
    private let screen = Vec(400, 800)

    func testScreenAndWorldMatchAtEveryZoom() {
        for pixel in Camera.pixels {
            let c = Camera(center: Vec(500, 800), pixel: pixel)
            XCTAssertEqual(c.world(screen * 0.5, screen).x, 500, accuracy: 1e-9)
            XCTAssertEqual(c.world(screen * 0.5, screen).y, 800, accuracy: 1e-9)
            XCTAssertEqual(c.rect(screen).w, 400 / (Double(pixel) / 2), accuracy: 1e-9)
        }
    }

    func testZoomIsWholePixelsAndKeepsThePointUnderTheFingers() {
        var c = Camera(center: Vec(500, 800), pixel: 3)
        let focus = Vec(100, 600)
        let under = c.world(focus, screen)
        c.zoom(to: 6, around: focus, screen)
        XCTAssertEqual(c.pixel, 6)
        XCTAssertEqual(c.world(focus, screen).x, under.x, accuracy: 1e-9)
        XCTAssertEqual(c.world(focus, screen).y, under.y, accuracy: 1e-9)
        c.zoom(to: 20, around: focus, screen)
        XCTAssertEqual(c.pixel, Camera.pixels.upperBound)
        c.zoom(to: 1, around: focus, screen)
        XCTAssertEqual(c.pixel, Camera.pixels.lowerBound)
    }

    func testPanFollowsTheFingerAndStaysOnTheMap() {
        var c = Camera(center: Vec(500, 800), pixel: 4) // 2 points per world unit
        c.pan(by: Vec(-100, 40))
        XCTAssertEqual(c.center, Vec(550, 780))
        let map = Vec(2000, 1600)
        c.pan(by: Vec(-100_000, 0))
        c.clamp(to: map, screen)
        XCTAssertEqual(c.rect(screen).x + c.rect(screen).w, 2000, accuracy: 1e-9)
        c.pan(by: Vec(0, 100_000))
        c.clamp(to: map, screen)
        XCTAssertEqual(c.rect(screen).y, 0, accuracy: 1e-9)
        var wide = Camera(center: .zero, pixel: 3)
        wide.clamp(to: Vec(200, 1600), screen) // map narrower than the screen: centred
        XCTAssertEqual(wide.center.x, 100)
    }

    func testDistrictUnderAPoint() {
        var w = World(seed: 1)
        XCTAssertEqual(w.district(at: Vec(1500, 10)), 0, "locked districts don't count")
        w.districts.append(District(index: 1))
        XCTAssertEqual(w.district(at: Vec(1500, 10)), 1)
        XCTAssertEqual(w.district(at: Vec(-5, 10)), 0)
    }

    func testMovingOutShowsASuitcase() {
        let fed = Bichito.Needs()
        XCTAssertEqual(Look.bubble(mood: .wander, needs: fed, dizzy: 0, moving: true), "🧳")
        XCTAssertNil(Look.bubble(mood: .wander, needs: fed, dizzy: 0, moving: false))
        XCTAssertEqual(Look.bubble(mood: .sleep, needs: fed, dizzy: 0, moving: true), "💤")
    }
}

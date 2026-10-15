import Foundation

/// What the screen looks at: a point of the map and a zoom. Screen sizes and points are in
/// screen points (y down). Pure, so pan and pinch maths is tested without SpriteKit.
struct Camera: Equatable {
    /// The four zoom levels of DESIGN.md: points per `u` (one sprite pixel) once the pinch settles.
    enum Level: Int, CaseIterable {
        case map, district, street, close

        var scale: Double { [1, 3, 5, 8][rawValue] }

        /// Nearest level, measured by ratio: pinching is multiplicative, so ×2 is as far from ×1 as ×4 from ×2.
        static func nearest(_ scale: Double) -> Level {
            allCases.min { abs(log($0.scale / scale)) < abs(log($1.scale / scale)) }!
        }
    }

    /// The pinch may scale anywhere in here; letting go snaps to a level.
    static let scales = Level.map.scale...Level.close.scale

    var center: Vec
    /// Points per `u` (a sprite pixel). Continuous while pinching.
    var scale: Double

    /// Points per sprite pixel actually drawn: the nearest whole number, so there are never mixels.
    var pixel: Int { max(1, Int(scale.rounded())) }
    var level: Level { .nearest(scale) }
    /// While the zoom springs to a level after a pinch: the spring, its scale and the point that stays put.
    private(set) var snap: Spring?
    private var snapTo = 0.0, snapFocus = Vec.zero

    init(center: Vec, scale: Double) {
        self.center = center
        self.scale = scale
    }

    /// Points per world unit: a sprite pixel is 2 world units, so a drawn body matches its collision radius.
    var unit: Double { scale / 2 }

    func rect(_ screen: Vec) -> Rect {
        let w = screen.x / unit, h = screen.y / unit
        return Rect(x: center.x - w / 2, y: center.y - h / 2, w: w, h: h)
    }

    func world(_ p: Vec, _ screen: Vec) -> Vec {
        let r = rect(screen)
        return Vec(r.x + p.x / unit, r.y + p.y / unit)
    }

    /// The finger moved by `d` points: the map follows it.
    mutating func pan(by d: Vec) { center = center - d * (1 / unit) }

    /// Zooms to `scale` (clamped to `scales`), keeping the map point under `focus` where it is.
    mutating func zoom(to scale: Double, around focus: Vec, _ screen: Vec) {
        let anchor = world(focus, screen)
        self.scale = min(max(scale, Camera.scales.lowerBound), Camera.scales.upperBound)
        center = anchor - focus * (1 / unit) + screen * (0.5 / unit)
    }

    /// The fingers let go at `focus`: from now on `settle` springs the zoom to the nearest level
    /// with `response 0.4, damping 0.8`, as in SwiftUI.
    mutating func release(around focus: Vec) {
        let response = 0.4, damping = 0.8
        snapTo = level.scale
        snapFocus = focus
        snap = Spring(x: scale - snapTo, v: 0, stiffness: pow(2 * .pi / response, 2), damping: 4 * .pi * damping / response)
    }

    /// A new pinch takes over from the spring.
    mutating func grab() { snap = nil }

    /// Advances the snap by `dt` seconds; at rest it lands exactly on the level and stops.
    mutating func settle(dt: Double, _ screen: Vec) {
        guard var s = snap else { return }
        let step = 1.0 / 240 // small steps keep the stiff spring stable through a long frame
        var left = dt
        while left > 0 {
            s.step(min(left, step))
            left -= step
        }
        let done = abs(s.x) < 1e-3 && abs(s.v) < 1e-2
        snap = done ? nil : s
        zoom(to: snapTo + (done ? 0 : s.x), around: snapFocus, screen)
    }

    /// Keeps the view on the unlocked map; along an axis where the map is smaller than the screen, it sits centred.
    mutating func clamp(to size: Vec, _ screen: Vec) {
        let half = screen * (0.5 / unit)
        func fit(_ c: Double, _ h: Double, _ s: Double) -> Double { 2 * h >= s ? s / 2 : min(max(c, h), s - h) }
        center = Vec(fit(center.x, half.x, size.x), fit(center.y, half.y, size.y))
    }
}

extension World {
    /// The district a map point belongs to (districts sit side by side, left to right).
    func district(at p: Vec) -> Int {
        min(max(Int((p.x / World.districtSize.x).rounded(.down)), 0), districts.count - 1)
    }
}

import Foundation

/// What the screen looks at: a point of the map and an integer zoom. Screen sizes and points are in
/// screen points (y down). Pure, so pan and pinch maths is tested without SpriteKit.
struct Camera: Equatable {
    /// Points per sprite pixel (DESIGN.md: ×3 to ×8). Always an integer, so there are never mixels.
    static let pixels = 3...8

    var center: Vec
    var pixel: Int

    /// Points per world unit: a sprite pixel is 2 world units, so a drawn body matches its collision radius.
    var unit: Double { Double(pixel) / 2 }

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

    /// Zooms to the nearest allowed pixel size, keeping the map point under `focus` where it is.
    mutating func zoom(to pixel: Int, around focus: Vec, _ screen: Vec) {
        let anchor = world(focus, screen)
        self.pixel = min(max(pixel, Camera.pixels.lowerBound), Camera.pixels.upperBound)
        center = anchor - focus * (1 / unit) + screen * (0.5 / unit)
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

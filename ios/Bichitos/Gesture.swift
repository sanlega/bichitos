import Foundation

/// One finger on the map, from touch-down to lift: tells a tap from a drag and measures the throw.
/// Points are in screen space (points, y down). Pure, so it is tested without UIKit.
struct Touch {
    /// A tap may wander this many points before it counts as a drag.
    static let slop = 10.0
    /// Only the last bit of motion counts for the throw, so slowing down before letting go drops it gently.
    static let throwWindow = 0.08

    enum Action: Equatable {
        case none, pet(Int), feed, grab(Int)
    }

    let target: Int?   // bichito under the finger at touch-down
    let foodMode: Bool
    let start: Vec
    private(set) var isDrag = false
    private var samples: [(p: Vec, t: Double)]

    init(at p: Vec, time: Double, target: Int?, foodMode: Bool) {
        start = p
        self.target = target
        self.foodMode = foodMode
        samples = [(p, time)]
    }

    /// Returns the action to start when the finger has just become a drag.
    mutating func move(to p: Vec, time: Double) -> Action {
        samples.append((p, time))
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
        guard !isDrag, (p - start).length > Touch.slop else { return .none }
        isDrag = true
        return target.map { .grab($0) } ?? .none
    }

    /// What lifting the finger without dragging does: pet a bichito, or drop food on the ground in food mode.
    var tapAction: Action {
        if isDrag { return .none }
        if let t = target { return .pet(t) }
        return foodMode ? .feed : .none
    }

    /// Points per second over the last `throwWindow`; zero when the finger stood still before lifting.
    func velocity(at time: Double) -> Vec {
        let recent = samples.filter { time - $0.t <= Touch.throwWindow }
        guard let first = recent.first, let end = recent.last, end.t - first.t > 0.005 else { return .zero }
        return (end.p - first.p) * (1 / (end.t - first.t))
    }
}

extension World {
    /// The bichito drawn under a world point: the closest body within its radius plus `pad` (finger slop).
    func bichito(at p: Vec, pad: Double) -> Int? {
        bichitos
            .filter { ($0.pos - p).length <= $0.recipe.radius + pad }
            .min { ($0.pos - p).length < ($1.pos - p).length }?.id
    }
}

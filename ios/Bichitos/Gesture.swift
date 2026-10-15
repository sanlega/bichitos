import Foundation

/// One finger on the map, from touch-down to lift: tells a tap from a drag and measures the throw.
/// Points are in screen space (points, y down). Pure, so it is tested without UIKit.
struct Touch {
    /// A tap may wander this many points before it counts as a drag.
    static let slop = 10.0
    /// Only the last bit of motion counts for the throw, so slowing down before letting go drops it gently.
    static let throwWindow = 0.08

    enum Action: Equatable {
        case none, peek(Int), feed, close, grab(Int), pan
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

    /// Returns the action to start when the finger has just become a drag: grab the bichito, or pan the map.
    mutating func move(to p: Vec, time: Double) -> Action {
        samples.append((p, time))
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
        guard !isDrag, (p - start).length > Touch.slop else { return .none }
        isDrag = true
        return target.map { .grab($0) } ?? .pan
    }

    /// What lifting the finger without dragging does: open a bichito's peek; on the ground, drop food in food mode
    /// or close the peek.
    var tapAction: Action {
        if isDrag { return .none }
        if let t = target { return .peek(t) }
        return foodMode ? .feed : .close
    }

    /// Points per second over the last `throwWindow`; zero when the finger stood still before lifting.
    func velocity(at time: Double) -> Vec {
        let recent = samples.filter { time - $0.t <= Touch.throwWindow }
        guard let first = recent.first, let end = recent.last, end.t - first.t > 0.005 else { return .zero }
        return (end.p - first.p) * (1 / (end.t - first.t))
    }
}

/// «Seguir» in `BichitoPeek`: the camera stays on one bichito until the user pans the map.
struct Follow: Equatable {
    private(set) var id: Int?

    mutating func start(_ id: Int) { self.id = id }
    mutating func stop() { id = nil }

    /// Panning hands the camera back to the user; grabbing or tapping doesn't.
    mutating func after(_ action: Touch.Action) { if action == .pan { id = nil } }

    /// Where the camera should look, or nil. Following stops for good once the bichito is gone (it ran away).
    mutating func target(in world: World) -> Vec? {
        guard let id else { return nil }
        guard let b = world.bichito(id) else { self.id = nil; return nil }
        return b.pos
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

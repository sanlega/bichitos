import Foundation

/// One finger on the map, from touch-down to lift: tells a tap, a drag and a rub apart and measures the throw.
/// Points are in screen space (points, y down). Pure, so it is tested without UIKit.
///
/// On the ground, moving past `slop` pans. On a bichito the finger is undecided while it stays within `reach`
/// (its hit radius) of where it came down: two direction reversals there within `rubWindow` make it a rub,
/// leaving `reach` first makes it a grab. A rub never turns into a grab.
struct Touch {
    /// A tap may wander this many points before it counts as a drag.
    static let slop = 10.0
    /// Only the last bit of motion counts for the throw, so slowing down before letting go drops it gently.
    static let throwWindow = 0.08
    /// A stroke must go this far before turning back counts as a reversal, so finger jitter never rubs.
    static let rubStroke = 6.0
    /// Two reversals this close in time make a rub.
    static let rubWindow = 0.8
    /// While rubbing, at most one pet this often.
    static let petEvery = 0.35

    enum Action: Equatable {
        case none, peek(Int), feed, close, grab(Int), pan, rub(Int)
    }

    let target: Int?   // bichito under the finger at touch-down
    let foodMode: Bool
    let start: Vec
    /// On a bichito, how far the finger may go from `start` before it grabs (never less than `slop`).
    let reach: Double
    private(set) var isDrag = false
    private(set) var isRub = false
    private var moved = false
    private var samples: [(p: Vec, t: Double)]
    private var anchor: Vec   // where the current stroke began
    private var tip: Vec      // furthest point of the current stroke
    private var reversals: [Double] = []
    private var lastPet = -Double.infinity

    init(at p: Vec, time: Double, target: Int?, foodMode: Bool, reach: Double = Touch.slop) {
        start = p
        self.target = target
        self.foodMode = foodMode
        self.reach = max(reach, Touch.slop)
        samples = [(p, time)]
        anchor = p
        tip = p
    }

    /// Returns the action the finger has just started: grab the bichito, pan the map, or pet it (again) by rubbing.
    mutating func move(to p: Vec, time: Double) -> Action {
        samples.append((p, time))
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
        if isDrag { return .none }
        let away = (p - start).length
        if away > Touch.slop { moved = true }
        guard let id = target else {
            guard moved else { return .none }
            isDrag = true
            return .pan
        }
        if reversed(at: p, time: time) {
            reversals.removeAll { time - $0 > Touch.rubWindow }
            if reversals.count >= 2 { isRub = true }
            if isRub, time - lastPet >= Touch.petEvery {
                lastPet = time
                return .rub(id)
            }
        }
        guard !isRub, away > reach else { return .none }
        isDrag = true
        return .grab(id)
    }

    /// Follows the stroke; true when the finger turned back after a stroke of at least `rubStroke`.
    private mutating func reversed(at p: Vec, time: Double) -> Bool {
        let stroke = tip - anchor, back = p - tip
        if (p - anchor).length >= stroke.length { tip = p; return false }
        guard stroke.length >= Touch.rubStroke, back.length >= Touch.rubStroke,
              stroke.x * back.x + stroke.y * back.y < 0 else { return false }
        reversals.append(time)
        anchor = tip
        tip = p
        return true
    }

    /// What lifting the finger without moving does: open a bichito's peek; on the ground, drop food in food mode
    /// or close the peek.
    var tapAction: Action {
        if isDrag || isRub || moved { return .none }
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

    /// VoiceOver «Lanzar»: thrown in a random direction, about as hard as a good flick.
    mutating func toss<G: RandomNumberGenerator>(_ id: Int, using rng: inout G) {
        let a = Double.random(in: 0..<2 * .pi, using: &rng)
        release(id, velocity: Vec(cos(a), sin(a)) * 900)
    }
}

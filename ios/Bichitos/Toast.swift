import Foundation

/// Queue of live events worth a toast: one on screen at a time, each for `duration` seconds.
/// Floods (the same kind and pair again within `window`) are dropped, and the queue holds at most `maxQueue`.
struct Toasts {
    static let window = 20.0
    static let maxQueue = 3
    var duration = 3.0
    private(set) var current: WorldEvent?
    private var until = 0.0
    private var queue: [WorldEvent] = []
    private var lastSeen: [String: Double] = [:]

    mutating func push(_ e: WorldEvent, at t: Double) {
        guard let k = Toasts.key(e) else { return }
        lastSeen = lastSeen.filter { t - $0.value < Toasts.window }
        guard lastSeen[k] == nil else { return }
        lastSeen[k] = t
        if queue.count < Toasts.maxQueue { queue.append(e) }
    }

    /// Advances the clock: the current toast leaves after `duration`, and the next one in line takes its place.
    mutating func update(at t: Double) {
        guard current == nil || t >= until else { return }
        current = queue.isEmpty ? nil : queue.removeFirst()
        until = t + duration
    }

    /// Kind and (unordered) pair; nil for events that never get a toast.
    static func key(_ e: WorldEvent) -> String? {
        switch e {
        case .fought: return nil
        case let .fellInLove(a, b): return "love \(min(a, b)) \(max(a, b))"
        case let .eggLaid(a, b): return "egg \(min(a, b)) \(max(a, b))"
        case let .hatched(c): return "hatched \(c)"
        case let .emigrated(a, _): return "moved \(a)"
        case let .escaped(a): return "escaped \(a)"
        case let .recovered(a): return "recovered \(a)"
        case let .unlocked(d, _): return "unlocked \(d)"
        }
    }
}

extension World {
    /// The toast line for a live event: the news feed's line, without a count.
    func toastText(_ e: WorldEvent) -> String { newsText(News.Item(event: e, date: date, place: .zero), language) }
}

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
        case let .unlocked(d): return "unlocked \(d)"
        }
    }
}

extension World {
    /// The toast line for a live event, in the world's language.
    func toastText(_ e: WorldEvent) -> String {
        let es = language == .es
        func name(_ id: Int) -> String {
            bichito(id)?.name ?? notes.first(where: { $0.bichito.id == id })?.bichito.name ?? "?"
        }
        func place(_ d: Int) -> String { d < districts.count ? districts[d].name(language) : "?" }
        switch e {
        case let .fought(a, b): return es ? "\(name(a)) y \(name(b)) se pelearon" : "\(name(a)) and \(name(b)) fought"
        case let .fellInLove(a, b): return es ? "\(name(a)) y \(name(b)) se enamoraron" : "\(name(a)) and \(name(b)) fell in love"
        case let .eggLaid(a, b): return es ? "\(name(a)) y \(name(b)) pusieron un huevo" : "\(name(a)) and \(name(b)) laid an egg"
        case let .hatched(c): return es ? "Nació \(name(c))" : "\(name(c)) hatched"
        case let .emigrated(a, d): return es ? "\(name(a)) se muda a \(place(d))" : "\(name(a)) is moving to \(place(d))"
        case let .escaped(a): return es ? "\(name(a)) se escapó" : "\(name(a)) ran away"
        case let .recovered(a): return es ? "\(name(a)) volvió a casa" : "\(name(a)) came back home"
        case let .unlocked(d): return es ? "Se abrió un barrio nuevo: \(place(d))" : "A new district opened: \(place(d))"
        }
    }
}

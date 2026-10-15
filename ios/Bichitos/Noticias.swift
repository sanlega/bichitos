import Foundation

/// The terrarium's news: the 20 most recent stories, newest first. Unlike `World.events` (the
/// "mientras no estabas" log) it is saved with the world and never cleared by `catchUp`.
struct News: Codable, Equatable {
    static let capacity = 20

    struct Item: Codable, Equatable {
        var event: WorldEvent // the kind of story; pairs stored lowest id first so both orders group together
        var date: Date        // of the latest time it happened
        var count = 1         // "se pelearon 14 veces" is one item with count 14
        var place: Vec        // where to point the camera, as of the latest time

        var bichitos: [Int] {
            switch event {
            case let .fought(a, b), let .fellInLove(a, b), let .eggLaid(a, b): return [a, b]
            case let .hatched(a), let .emigrated(a, _), let .escaped(a), let .recovered(a): return [a]
            case .unlocked: return []
            }
        }
    }

    private(set) var items: [Item] = []

    /// A repeat of a story already in the list bumps its count and date and moves it to the top.
    mutating func add(_ event: WorldEvent, date: Date, place: Vec) {
        let e = News.story(event)
        var item = Item(event: e, date: date, place: place)
        if let k = items.firstIndex(where: { $0.event == e }) {
            item.count = items.remove(at: k).count + 1
        }
        items.insert(item, at: 0)
        if items.count > News.capacity { items.removeLast(items.count - News.capacity) }
    }

    /// The event as stored: pairs lowest id first, so both orders are the same story.
    static func story(_ event: WorldEvent) -> WorldEvent {
        switch event {
        case let .fought(a, b): return .fought(min(a, b), max(a, b))
        case let .fellInLove(a, b): return .fellInLove(min(a, b), max(a, b))
        default: return event
        }
    }

    /// Where a live event (a toast) happened, as of its latest time.
    func place(of event: WorldEvent) -> Vec? { items.first { $0.event == News.story(event) }?.place }

    /// «hace 3 min» / "3 min ago"; under a minute, «ahora» / "just now".
    static func ago(_ date: Date, now: Date, _ language: Language) -> String {
        let s = max(0, now.timeIntervalSince(date)), es = language == .es
        let n: Int, unit: String
        switch s {
        case ..<60: return es ? "ahora" : "just now"
        case ..<3600: (n, unit) = (Int(s / 60), "min")
        case ..<86400: (n, unit) = (Int(s / 3600), "h")
        default: (n, unit) = (Int(s / 86400), "d")
        }
        return es ? "hace \(n) \(unit)" : "\(n) \(unit) ago"
    }
}

extension World {
    var news: News {
        get { newsLog ?? News() }
        set { newsLog = newValue }
    }

    /// Called for every recorded event.
    mutating func report(_ e: WorldEvent) {
        let place: Vec?
        switch e {
        case let .fought(a, _), let .fellInLove(a, _), let .eggLaid(a, _), let .hatched(a), let .recovered(a):
            place = bichito(a)?.pos
        case let .escaped(a): place = notes.last(where: { $0.bichito.id == a })?.pos
        case let .emigrated(_, d), let .unlocked(d, _): place = districts[d].rect.center
        }
        news.add(e, date: date, place: place ?? districts[0].rect.center)
    }

    /// One line for the news feed or a toast: "Chencho y Ramona se pelearon 14 veces."
    func newsText(_ item: News.Item, _ language: Language) -> String {
        let es = language == .es
        func name(_ id: Int) -> String {
            bichito(id)?.name ?? notes.first(where: { $0.bichito.id == id })?.bichito.name ?? "?"
        }
        func place(_ d: Int) -> String { districts.indices.contains(d) ? districts[d].name(language) : "?" }
        let line: String
        switch item.event {
        case let .fought(a, b): line = es ? "\(name(a)) y \(name(b)) se pelearon" : "\(name(a)) and \(name(b)) fought"
        case let .fellInLove(a, b): line = es ? "\(name(a)) y \(name(b)) se enamoraron" : "\(name(a)) and \(name(b)) fell in love"
        case let .eggLaid(a, b): line = es ? "\(name(a)) y \(name(b)) pusieron un huevo" : "\(name(a)) and \(name(b)) laid an egg"
        case let .hatched(c): line = es ? "Nació \(name(c))" : "\(name(c)) was born"
        case let .emigrated(a, d): line = es ? "\(name(a)) se mudó a \(place(d))" : "\(name(a)) moved to \(place(d))"
        case let .escaped(a): line = es ? "\(name(a)) se escapó" : "\(name(a)) ran away"
        case let .recovered(a): line = es ? "\(name(a)) volvió a casa" : "\(name(a)) came back home"
        case let .unlocked(d, _): line = es ? "Se abrió un barrio nuevo: \(place(d))" : "A new district opened: \(place(d))"
        }
        guard item.count > 1 else { return line + "." }
        return line + (es ? " \(item.count) veces." : " \(item.count) times.")
    }
}

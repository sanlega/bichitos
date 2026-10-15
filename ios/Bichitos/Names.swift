import Foundation

enum Language: String, Codable, CaseIterable { case es, en }

/// Generated names, absurd descriptions and goodbye notes. Deterministic from a seed.
extension World {
    /// Names of the living and of the escaped (their notes), which a generated name avoids.
    var takenNames: Set<String> { Set(bichitos.map(\.name) + notes.map(\.bichito.name)) }
}

enum Names {
    /// `name` replaces the generated name (the editor lets you type one) and keeps the same quirks.
    /// A generated name avoids `taken` (`World.takenNames`); a typed one is kept even if repeated.
    static func make(seed: UInt64, language: Language, name custom: String? = nil, taken: Set<String> = []) -> (name: String, description: String) {
        var rng = SeededRNG(seed: seed)
        let names = language == .es ? namesEs : namesEn
        let quirks = language == .es ? quirksEs : quirksEn
        let picked = names.firstIndex(of: names.randomElement(using: &rng)!)!
        let name = custom ?? unique(from: picked, names: names, language: language, taken: taken)
        let age = Int.random(in: 1...9, using: &rng)
        let i = Int.random(in: 0..<quirks.count, using: &rng)
        var j = Int.random(in: 0..<(quirks.count - 1), using: &rng)
        if j >= i { j += 1 }
        switch language {
        case .es:
            let years = age == 1 ? "año" : "años"
            return (name, "\(name), \(age) \(years), \(quirks[i]) y \(quirks[j]).")
        case .en:
            let years = age == 1 ? "year" : "years"
            return (name, "\(name), \(age) \(years) old, \(quirks[i]) and \(quirks[j]).")
        }
    }

    /// The first free name walking the list from `start`; once all are taken, the same walk with a suffix
    /// («Tolón II», «Tolón el Joven»), and past those a plain number. Uses no randomness, so the quirks stay put.
    static func unique(from start: Int, names: [String], language: Language, taken: Set<String>) -> String {
        for suffix in [""] + (language == .es ? suffixesEs : suffixesEn) {
            for k in 0..<names.count {
                let candidate = names[(start + k) % names.count] + suffix
                if !taken.contains(candidate) { return candidate }
            }
        }
        var n = 2
        while taken.contains("\(names[start]) \(n)") { n += 1 }
        return "\(names[start]) \(n)"
    }

    static let suffixesEs = [" II", " el Joven", " III", " el Breve", " IV", " el Magnífico", " V", " el Otro"]
    static let suffixesEn = [" II", " Jr.", " III", " the Brief", " IV", " the Magnificent", " V", " the Other"]

    static func goodbye(name: String, seed: UInt64, language: Language) -> String {
        var rng = SeededRNG(seed: seed)
        let line = (language == .es ? goodbyesEs : goodbyesEn).randomElement(using: &rng)!
        return "\(line) — \(name)"
    }

    static let namesEs = [
        "Pocholo", "Chencho", "Ramona", "Gominola", "Peluso", "Lula", "Fofito", "Chispa", "Bombón", "Tronchi",
        "Pimpollo", "Cuqui", "Rufino", "Bizcocho", "Chuli", "Mofli", "Garbancito", "Pelusa", "Turrón", "Zapatilla",
        "Ñoqui", "Rosquilla", "Tolón", "Pirulo", "Trufa", "Croqueta", "Merengue", "Chuchi", "Lenteja", "Pantuflo",
        "Remigio", "Cachito", "Fideo", "Petra", "Maripili", "Toribio", "Burbuja",
    ]
    static let namesEn = [
        "Pickles", "Noodle", "Biscuit", "Waffles", "Bumble", "Gizmo", "Muffin", "Pudding", "Sprout", "Bubbles",
        "Doodle", "Peanut", "Nugget", "Pebble", "Wobble", "Tater", "Marshmallow", "Jellybean", "Fuzzball", "Pumpkin",
        "Crumpet", "Dumpling", "Socks", "Turnip", "Bean", "Mittens", "Pip", "Tofu", "Gumdrop", "Sprinkles",
        "Zigzag", "Bloop", "Cupcake", "Scooter", "Snickerdoodle",
    ]
    // Spanish quirks never start with "i"/"hi", so joining them with "y" always reads right.
    static let quirksEs = [
        "odia las esquinas", "sospecha de las nubes", "colecciona migas", "le habla a las piedras",
        "cree que es una seta", "duerme con un ojo abierto", "tiene miedo de su sombra", "baila cuando nadie mira",
        "desconfía de los lunes", "cuenta las hormigas", "quiere ser astronauta", "se ríe de los charcos",
        "saluda a las farolas", "nunca ha visto el mar", "solo come cosas verdes", "escribe poemas a las tostadas",
        "se pierde en línea recta", "jura que vio un dragón", "ronca en dos idiomas", "guarda secretos de las palomas",
        "practica kárate con las hojas", "opina sobre todo", "se asusta con los estornudos", "ama los calcetines desparejados",
        "persigue una cola que no tiene", "lleva la cuenta de los bostezos", "cree que la luna le sigue", "canta mal pero con ganas",
        "le tiene manía al viento", "se esconde de las mariposas", "sueña con ser un sombrero", "prefiere andar de lado",
        "pide perdón a las sillas", "confunde las nubes con ovejas", "tararea en los ascensores", "mira fijamente a las paredes",
        "colecciona botones perdidos", "desconfía de las cucharas", "aplaude cuando aterrizan los aviones", "se ofende con los relojes",
        "nunca termina una frase", "tiene un amigo imaginario muy pesado", "se peina con el viento", "cree que los árboles cotillean",
    ]
    static let quirksEn = [
        "hates corners", "is suspicious of clouds", "collects crumbs", "talks to rocks",
        "thinks it is a mushroom", "sleeps with one eye open", "is afraid of its own shadow", "dances when nobody is looking",
        "distrusts Mondays", "counts ants", "wants to be an astronaut", "laughs at puddles",
        "waves at lampposts", "has never seen the sea", "only eats green things", "writes poems to toast",
        "gets lost walking in a straight line", "swears it saw a dragon", "snores in two languages", "keeps secrets for pigeons",
        "does karate with leaves", "has opinions about everything", "is startled by sneezes", "loves odd socks",
        "chases a tail it does not have", "keeps count of yawns", "thinks the moon follows it", "sings badly but loudly",
        "holds a grudge against the wind", "hides from butterflies", "dreams of being a hat", "prefers walking sideways",
        "apologizes to chairs", "mistakes clouds for sheep", "hums in elevators", "stares at walls",
        "collects lost buttons", "distrusts spoons", "claps when planes land", "is offended by clocks",
        "never finishes a sentence", "has a very annoying imaginary friend", "combs its hair with the wind", "thinks trees gossip",
    ]
    static let goodbyesEs = [
        "Me voy a buscar una esquina que me quiera.", "Me he ido a ver mundo. Volveré si hay galletas.",
        "Necesito espacio. Mucho. Un barrio entero.", "Me voy con los patos. Ellos sí me entienden.",
        "Aquí nadie me hace caso. Ni las nubes.", "He salido a por pan. Para siempre.",
        "Me escapo a ser famoso. No me esperéis despiertos.", "Tengo hambre y dignidad. Sobre todo hambre.",
        "Me voy a vivir debajo de una seta.", "Si me quieres, deja comida aquí.",
        "Me he ido a pensar en mis cosas.", "Vuelvo cuando alguien me haga un mimo.",
    ]
    static let goodbyesEn = [
        "I'm off to find a corner that loves me.", "Gone to see the world. Will return for biscuits.",
        "I need space. Lots. A whole district.", "I'm going to live with the ducks. They get me.",
        "Nobody pays attention to me here. Not even the clouds.", "Went out for bread. Forever.",
        "Running away to be famous. Don't wait up.", "I have hunger and dignity. Mostly hunger.",
        "I'm moving under a mushroom.", "If you love me, leave food here.",
        "Gone to think about my stuff.", "I'll be back when someone pets me.",
    ]
}

import Foundation

/// Short things a bichito says in its bubble, from its mood and personality. Deterministic from a seed, es + en.
enum Phrases {
    enum Situation: CaseIterable { case idle, hungry, sleepy, love, scared, fight, thrown, held, happy, meet, egg }

    static func situation(mood: Bichito.Mood, needs: Bichito.Needs, dizzy: Double) -> Situation {
        if dizzy > 0.5 { return .thrown }
        switch mood {
        case .sleep, .toBed: return .sleepy
        case .love: return .love
        case .fight: return .fight
        case .scared, .flee: return .scared
        case .eat: return .hungry
        case .happy: return .happy
        case .held: return .held
        case .chase, .imitate: return .meet
        case .incubating: return .egg
        case .wander: return needs.hunger < 0.3 ? .hungry : needs.sleep < 0.2 ? .sleepy : .idle
        }
    }

    static func say(mood: Bichito.Mood, needs: Bichito.Needs, dizzy: Double, personality: Recipe.Personality,
                    seed: UInt64, language: Language) -> String {
        make(situation(mood: mood, needs: needs, dizzy: dizzy), personality: personality, seed: seed, language: language)
    }

    static func make(_ situation: Situation, personality: Recipe.Personality, seed: UInt64, language: Language) -> String {
        var rng = SeededRNG(seed: seed)
        let es = language == .es
        var line = lines(situation, es: es).randomElement(using: &rng)!
        line = line.replacingOccurrences(of: "%t", with: (es ? thingsEs : thingsEn).randomElement(using: &rng)!)
        line = line.replacingOccurrences(of: "%f", with: (es ? foodsEs : foodsEn).randomElement(using: &rng)!)
        let tic = tics(personality, es: es).randomElement(using: &rng)!
        if Bool.random(using: &rng), line.count + tic.count < 34 { line += " " + tic }
        return capitalized(line)
    }

    /// Upper-cases the first letter, after any "¡" or "¿".
    private static func capitalized(_ s: String) -> String {
        guard let i = s.firstIndex(where: { $0.isLetter }) else { return s }
        return String(s[..<i]) + s[i].uppercased() + String(s[s.index(after: i)...])
    }

    // "%t" is a thing with its demonstrative, "%f" a food with its article.
    static let thingsEs = ["esa nube", "esa farola", "ese calcetín", "esa piedra", "esa hoja", "ese charco",
                           "esa cuchara", "esa mosca", "ese botón", "esa seta", "esa esquina", "ese pájaro"]
    static let thingsEn = ["that cloud", "that lamppost", "that sock", "that rock", "that leaf", "that puddle",
                           "that spoon", "that fly", "that button", "that mushroom", "that corner", "that bird"]
    static let foodsEs = ["una tostada", "un macarrón", "una miga", "un guisante", "una galleta", "un fideo", "una croqueta"]
    static let foodsEn = ["toast", "a noodle", "a crumb", "a pea", "a biscuit", "a waffle", "a dumpling"]

    static func lines(_ s: Situation, es: Bool) -> [String] {
        switch s {
        case .idle:
            return es ? ["¡%t me mira!", "¿%t habla?", "Hoy me siento redondo.", "Creo que %t me sigue.",
                         "¿Quién ha movido el suelo?", "Tengo una idea. Ya no.", "Me pica la oreja. No tengo oreja.",
                         "¿Y si soy una seta?", "No me fío de %t.", "¿Hoy es lunes? Huele a lunes."]
                : ["%t is staring at me!", "Does %t talk?", "I feel very round today.", "I think %t follows me.",
                   "Who moved the floor?", "I had an idea. It left.", "My ear itches. I have no ears.",
                   "What if I'm a mushroom?", "I don't trust %t.", "Is it Monday? Smells like Monday."]
        case .hungry:
            return es ? ["Tengo hambre de %f.", "¡Mi tripa ruge!", "Soñé con %f.", "¿Eso se come?",
                         "Me comería %t.", "Hambre. Mucha. Toda.", "¿Alguien ha dicho %f?"]
                : ["I'm hungry for %f.", "My tummy is roaring!", "I dreamt of %f.", "Can I eat that?",
                   "I could eat %t.", "Hungry. Very. All of it.", "Did someone say %f?"]
        case .sleepy:
            return es ? ["Cinco minutitos más...", "Zzz... %f... zzz", "No duermo, pienso.", "Soñando con %t...",
                         "Mmm... qué blandito...", "Shh, que sueño."]
                : ["Five more minutes...", "Zzz... %f... zzz", "Not asleep. Thinking.", "Dreaming of %t...",
                   "Mmm... so squishy...", "Shh, I'm dreaming."]
        case .love:
            return es ? ["¡Qué ojos tienes!", "Me late todo el cuerpo.", "¿Compartimos %f?", "Eres más mono que %t.",
                         "¡Te quiero un montón!", "Me haces cosquillas por dentro."]
                : ["What lovely eyes!", "My whole body is beating.", "Shall we share %f?", "You're cuter than %t.",
                   "I love you a whole bunch!", "You tickle my insides."]
        case .scared:
            return es ? ["¡Socorro!", "¡%t me persigue!", "¡Ay, ay, ay!", "¡Que viene!", "¡Yo no he sido!", "¡Mamáaa!"]
                : ["Help!", "%t is chasing me!", "Oh no, oh no!", "It's coming!", "It wasn't me!", "Mommy!"]
        case .fight:
            return es ? ["¡Este charco es mío!", "¡Retira eso!", "¡Mira mi cara de enfado!", "¡Te voy a despeinar!",
                         "¡A que no me pillas!", "¡Mi abuela pega más fuerte!"]
                : ["This puddle is mine!", "Take that back!", "Behold my angry face!", "I'll mess up your hair!",
                   "Bet you can't catch me!", "My granny hits harder!"]
        case .thrown:
            return es ? ["¡Wiiiii!", "¿Dónde está el suelo?", "Veo estrellitas...", "¡Otra vez! No. Sí.",
                         "Mi cabeza da vueltas.", "¡Sé volar! Más o menos."]
                : ["Wheeee!", "Where did the floor go?", "I see little stars...", "Again! No. Yes.",
                   "My head is spinning.", "I can fly! Sort of."]
        case .held:
            return es ? ["¡Bájame!", "Qué alto se está aquí.", "¡Cuidado, que soy frágil!", "¿A dónde vamos?", "Huele a manos."]
                : ["Put me down!", "It's so high up here.", "Careful, I'm fragile!", "Where are we going?", "Smells like hands."]
        case .happy:
            return es ? ["¡Qué día más bonito!", "¡Me encanta %t!", "La la la...", "¡Feliz como %f!",
                         "¡Mírame bailar!", "¡Hoy todo es blandito!"]
                : ["What a lovely day!", "I love %t!", "La la la...", "Happy as %f!",
                   "Watch me dance!", "Everything is squishy today!"]
        case .meet:
            return es ? ["¡Hola, desconocido!", "¿Tú también eres redondo?", "¿Me prestas %t?", "Te sigo. No sé por qué.",
                         "¿Jugamos a imitarnos?", "¿Te conozco de algo?"]
                : ["Hello, stranger!", "Are you round too?", "Can I borrow %t?", "Following you. Not sure why.",
                   "Wanna copy each other?", "Have we met?"]
        case .egg:
            return es ? ["Shh, estoy incubando.", "Este huevo se parece a mí.", "Crece, huevito, crece.",
                         "Seré un gran padre. O madre.", "No toques el huevo."]
                : ["Shh, I'm hatching.", "This egg looks like me.", "Grow, little egg, grow.",
                   "I'll be a great parent.", "Don't touch the egg."]
        }
    }

    /// A little sign-off that gives away the personality.
    static func tics(_ p: Recipe.Personality, es: Bool) -> [String] {
        switch p {
        case .curiosa: return es ? ["¿Y eso?", "¿Por qué?", "Mmm."] : ["Why?", "Hmm?", "What's that?"]
        case .nerviosa: return es ? ["¡Ay!", "¡Ay, ay!", "¡Socorro!"] : ["Eek!", "Oh no.", "Help!"]
        case .dormilona: return es ? ["Zzz...", "Uaaah.", "Mmm..."] : ["Zzz...", "Yawn.", "Mmm..."]
        case .hiperactiva: return es ? ["¡Ya!", "¡Vamos!", "¡Wiii!"] : ["Now!", "Go go!", "Wheee!"]
        case .territorial: return es ? ["¡Es mío!", "Grr.", "¡Fuera!"] : ["Mine!", "Grr.", "Back off!"]
        case .romantica: return es ? ["Ay, amor.", "Mua.", "Suspiro."] : ["Sigh.", "Smooch.", "Oh, love."]
        }
    }
}

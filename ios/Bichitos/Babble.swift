import Foundation

/// How a bichito sounds. Built from genes only (never the seed), so a child's voice blends its parents'.
struct VoiceParams: Equatable {
    var pitch: Double  // Hz of the glottal source at rest
    var rate: Double   // letters per second
    var swing: Double  // semitones of melody
    var bright: Double // formant scale: above 1 is a smaller, squeakier mouth
    var breath: Double // 0...1 noise in the source
}

extension Recipe {
    var voice: VoiceParams {
        let shape: Double // octaves
        switch body {
        case .torre: shape = -0.25
        case .pera: shape = -0.15
        case .cuadradito: shape = -0.1
        case .gota: shape = 0
        case .alubia: shape = 0.05
        case .estrella: shape = 0.15
        }
        let tempo: (rate: Double, swing: Double)
        switch personality {
        case .hiperactiva: tempo = (22, 6)
        case .nerviosa: tempo = (20, 7)
        case .curiosa: tempo = (16, 5)
        case .territorial: tempo = (15, 2)
        case .romantica: tempo = (13, 4)
        case .dormilona: tempo = (10, 1.5)
        }
        let eyeTone: Double
        switch eyes {
        case .ciclope: eyeTone = 0.9
        case .adormilados: eyeTone = 0.95
        case .normales: eyeTone = 1
        case .tres: eyeTone = 1.05
        case .saltones: eyeTone = 1.15
        }
        return VoiceParams(pitch: 300 * pow(2, (0.5 - height) * 1.2 + shape), // taller = bigger = lower
                           rate: tempo.rate * (0.9 + 0.2 * legLength), swing: tempo.swing,
                           bright: eyeTone * (1.05 + 0.3 * eyeSize), breath: 0.05 + 0.3 * bumps)
    }
}

/// RBJ band-pass, 0 dB at the centre.
struct BandPass {
    private var b0: Float = 0, a1: Float = 0, a2: Float = 0
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    mutating func tune(_ f: Float, q: Float, sampleRate: Float) {
        let w = 2 * Float.pi * min(f, sampleRate * 0.45) / sampleRate
        let alpha = sin(w) / (2 * q), a0 = 1 + alpha
        b0 = alpha / a0
        a1 = -2 * cos(w) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * (x - x2) - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Animal-Crossing-style babble: one short sound per character. Vowels are a saw through three formants,
/// consonants a burst of band-passed noise, all on a pitch contour that rises for questions. Pure DSP.
struct Babble {
    struct Sound {
        var length: Double // in letters (1 / rate seconds)
        var voiced: Float = 0
        var noise: Float = 0
        var burst = 1.0 // fraction of the sound the noise lasts
        var formants: (Float, Float, Float) = (500, 1500, 2500)
        var hiss: Float = 3000
    }

    static let schwa: (Float, Float, Float) = (500, 1500, 2500)
    static let vowels: [Character: (Float, Float, Float)] = [
        "a": (800, 1250, 2600), "e": (450, 1900, 2600), "i": (300, 2300, 3000),
        "o": (480, 850, 2600), "u": (330, 750, 2400), "y": (300, 2300, 3000),
    ]

    static func sound(_ c: Character) -> Sound {
        let letter = String(c).lowercased().folding(options: .diacriticInsensitive, locale: nil).first ?? c
        if let f = vowels[letter] { return Sound(length: 1, voiced: 1, formants: f) }
        switch letter {
        case " ": return Sound(length: 0.6)
        case ",", ".", "!", "?", "…", ";", ":": return Sound(length: 1.2)
        case "s", "z", "c", "x": return Sound(length: 0.7, voiced: 0.15, noise: 0.9, burst: 0.8, formants: schwa, hiss: 6000)
        case "f", "j", "h", "v", "g": return Sound(length: 0.6, voiced: 0.3, noise: 0.8, burst: 0.6, formants: schwa, hiss: 2200)
        case "p", "b", "t", "d", "k", "q": return Sound(length: 0.6, voiced: 0.6, noise: 1, burst: 0.25, formants: schwa, hiss: 1500)
        case "m", "n", "l", "r", "w": return Sound(length: 0.6, voiced: 0.8, formants: (300, 1100, 2400))
        default: return Sound(length: letter.isLetter || letter.isNumber ? 0.6 : 0, voiced: 0.6, formants: schwa)
        }
    }

    /// When each character starts, in seconds, plus the end. The bubble reveals its text on this clock.
    static func timeline(_ text: String, voice: VoiceParams) -> [Double] {
        var t = 0.0
        return [0] + text.map { c -> Double in
            t += sound(c).length / voice.rate
            return t
        }
    }

    /// The whole phrase through the same mixer the app uses; `count` pads with silence or cuts.
    static func render(_ text: String, voice: VoiceParams, sampleRate: Double = 44_100, count: Int? = nil) -> [Float] {
        let babble = Babble(text, voice: voice, sampleRate: sampleRate)
        var mixer = Mixer()
        mixer.add(babble, id: 0)
        return (0..<(count ?? babble.duration)).map { _ in mixer.next() }
    }

    let sampleRate: Float
    private let sounds: [Sound]
    private let ends: [Int] // sample where each sound ends
    private let pitches: [Float]
    private let breath: Float
    private let bright: Float
    private var t = 0
    private var index = 0
    private var entered = -1
    private var phase: Float = 0
    private var rng: UInt32 = 0x9E37_79B9
    private var f1 = BandPass(), f2 = BandPass(), f3 = BandPass(), hiss = BandPass()

    var duration: Int { ends.last ?? 0 }
    var done: Bool { index >= sounds.count }

    init(_ text: String, voice: VoiceParams, sampleRate: Double = 44_100) {
        let chars = Array(text)
        self.sampleRate = Float(sampleRate)
        sounds = chars.map(Babble.sound)
        ends = Babble.timeline(text, voice: voice).dropFirst().map { Int($0 * sampleRate) }
        breath = Float(voice.breath)
        bright = Float(voice.bright)
        let question = text.contains("?"), shout = text.contains("!")
        pitches = chars.enumerated().map { pair -> Float in
            let (i, c) = pair
            let x = chars.count > 1 ? Double(i) / Double(chars.count - 1) : 0
            var semis = -0.3 * voice.swing * x // a sentence falls gently
            if question { semis += 1.2 * voice.swing * max(0, x - 0.6) / 0.4 }
            if shout { semis += 2 + 0.5 * voice.swing * (1 - x) }
            // Same letter in the same place always wobbles the same way, so a phrase always sounds alike.
            var g = SeededRNG(seed: UInt64(c.unicodeScalars.first?.value ?? 0) &* 1_000_003 &+ UInt64(i))
            semis += voice.swing * 0.35 * (Double(g.next() >> 11) / Double(1 << 53) - 0.5)
            return Float(voice.pitch * pow(2, semis / 12))
        }
    }

    mutating func next() -> Float {
        while index < sounds.count && t >= ends[index] { index += 1 }
        guard index < sounds.count else { return 0 }
        let s = sounds[index]
        if entered != index {
            entered = index
            f1.tune(s.formants.0 * bright, q: 5, sampleRate: sampleRate)
            f2.tune(s.formants.1 * bright, q: 7, sampleRate: sampleRate)
            f3.tune(s.formants.2 * bright, q: 9, sampleRate: sampleRate)
            hiss.tune(s.hiss, q: 1.5, sampleRate: sampleRate)
        }
        let start = index == 0 ? 0 : ends[index - 1]
        let pos = t - start, len = ends[index] - start
        t += 1
        // Short fades on every sound hide the jumps in the filters.
        let env = max(0, min(1, Float(pos) / (sampleRate * 0.004), Float(len - pos) / (sampleRate * 0.012)))

        phase += pitches[index] / sampleRate
        if phase >= 1 { phase -= 1 }
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        let noise = Float(rng) / Float(UInt32.max) * 2 - 1
        let source = (1 - 2 * phase) * (1 - breath) + noise * breath
        var out = s.voiced * (f1.process(source) + 0.7 * f2.process(source) + 0.35 * f3.process(source))
        let hissed = hiss.process(noise)
        if Double(pos) < s.burst * Double(len) { out += s.noise * 0.6 * hissed }
        return out * env * 1.6
    }
}

/// Mixes the babbles playing at once. At most `maxVoices`: a new one drops the oldest, so a crowd never saturates.
struct Mixer {
    struct Voice {
        let id: Int
        var babble: Babble
    }

    static let maxVoices = 3
    private(set) var voices: [Voice] = []

    init() { voices.reserveCapacity(Mixer.maxVoices + 1) }

    /// The same speaker starting a new phrase replaces its old one.
    mutating func add(_ babble: Babble, id: Int) {
        voices.removeAll { $0.id == id }
        // shortcut: the dropped voice is cut, not faded; fade it out if the click is audible on device.
        if voices.count >= Mixer.maxVoices { voices.removeFirst() }
        voices.append(Voice(id: id, babble: babble))
    }

    mutating func next() -> Float {
        var sum: Float = 0, finished = false
        for i in voices.indices {
            sum += voices[i].babble.next()
            finished = finished || voices[i].babble.done
        }
        if finished { voices.removeAll { $0.babble.done } }
        return tanhf(sum) // soft clip: never past ±1
    }
}

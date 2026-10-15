import XCTest
@testable import Bichitos

final class VoiceTests: XCTestCase {
    private let moods: [Bichito.Mood] = [.wander, .sleep, .eat, .love, .fight, .chase, .flee, .imitate, .scared, .happy, .held, .incubating]

    private func recipe(_ seed: UInt64) -> Recipe {
        var rng = SeededRNG(seed: seed)
        return Recipe.random(using: &rng)
    }

    func testPhrasesAreDeterministicAndExistForEveryMoodInBothLanguages() {
        let cases: [(Bichito.Mood, Double)] = moods.map { ($0, 0) } + [(.wander, 2)] // the last one was thrown
        for language in Language.allCases {
            for (mood, dizzy) in cases {
                for personality in Recipe.Personality.allCases {
                    var seen = Set<String>()
                    for seed in UInt64(1)...20 {
                        let line = Phrases.say(mood: mood, needs: Bichito.Needs(), dizzy: dizzy, personality: personality,
                                               seed: seed, language: language)
                        XCTAssertEqual(line, Phrases.say(mood: mood, needs: Bichito.Needs(), dizzy: dizzy,
                                                         personality: personality, seed: seed, language: language))
                        XCTAssertFalse(line.isEmpty)
                        XCTAssertFalse(line.contains("%"), line)
                        XCTAssertLessThanOrEqual(line.count, 40, line)
                        seen.insert(line)
                    }
                    XCTAssertGreaterThan(seen.count, 3, "\(mood) \(personality) \(language)")
                }
            }
        }
    }

    func testRenderIsAudibleFiniteAndUnclipped() {
        for seed in UInt64(1)...8 {
            let samples = Babble.render("¡Hola! ¿Esa nube me mira?", voice: recipe(seed).voice)
            XCTAssertGreaterThan(samples.count, 4410)
            XCTAssertFalse(samples.contains { !$0.isFinite })
            XCTAssertLessThanOrEqual(samples.map { abs($0) }.max() ?? 2, 1)
            let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
            XCTAssertGreaterThan(rms, 0.02, "seed \(seed)")
        }
        XCTAssertEqual(Babble.render("hola", voice: recipe(1).voice, count: 100_000).count, 100_000)
    }

    func testAudioFollowsTheBubbleClock() {
        let voice = recipe(2).voice, text = "Tengo hambre de una tostada."
        let times = Babble.timeline(text, voice: voice)
        XCTAssertEqual(times.count, text.count + 1)
        XCTAssertEqual(Double(Babble(text, voice: voice).duration) / 44_100, times.last!, accuracy: 0.001)
    }

    func testSmallerRecipesSpeakHigherAndSeedDoesNotChangeTheVoice() {
        for seed in UInt64(1)...12 {
            var small = recipe(seed), big = small
            small.height = 0.1
            big.height = 0.9
            XCTAssertGreaterThan(small.voice.pitch, big.voice.pitch)
            var other = small
            other.seed &+= 1
            XCTAssertEqual(other.voice, small.voice)
        }
    }

    func testVoiceCountIsCapped() {
        var mixer = Mixer()
        let voice = recipe(3).voice
        for id in 0..<5 { mixer.add(Babble("¡Hola a todos!", voice: voice), id: id) }
        XCTAssertEqual(mixer.voices.map { $0.id }, [2, 3, 4])
        mixer.add(Babble("Otra vez.", voice: voice), id: 3)
        XCTAssertEqual(mixer.voices.map { $0.id }, [2, 4, 3])
        var peak: Float = 0
        for _ in 0..<20_000 { peak = max(peak, abs(mixer.next())) }
        XCTAssertLessThanOrEqual(peak, 1)
        XCTAssertGreaterThan(peak, 0.05)
    }

    /// Writes `voices.wav` (and what each one says in `voices.txt`) to `GALLERY_DIR`, to listen to in the CI artifact.
    func testWriteVoices() throws {
        guard let dir = ProcessInfo.processInfo.environment["GALLERY_DIR"], !dir.isEmpty else {
            throw XCTSkip("GALLERY_DIR not set")
        }
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var samples: [Float] = [], script: [String] = []
        let gap = [Float](repeating: 0, count: 13_000)
        for (n, seed) in (UInt64(1)...10).enumerated() {
            var r = recipe(seed)
            r.personality = Recipe.Personality.allCases[n % Recipe.Personality.allCases.count]
            let language: Language = n % 2 == 0 ? .es : .en
            let line = Phrases.say(mood: moods[n % moods.count], needs: Bichito.Needs(), dizzy: 0,
                                   personality: r.personality, seed: seed, language: language)
            samples += Babble.render(line, voice: r.voice) + gap
            script.append(String(format: "%@ (%@, %@, height %.2f, %.0f Hz): %@", r.body.rawValue, r.personality.rawValue,
                                 r.eyes.rawValue, r.height, r.voice.pitch, line))
        }
        try wav(samples).write(to: out.appendingPathComponent("voices.wav"))
        try script.joined(separator: "\n").write(to: out.appendingPathComponent("voices.txt"), atomically: true, encoding: .utf8)
    }

    /// 16-bit mono PCM at 44.1 kHz.
    private func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + samples.count * 2)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(44_100); u32(88_200); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count * 2))
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        return d
    }
}

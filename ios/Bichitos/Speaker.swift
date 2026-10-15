import AVFoundation
import os

/// Plays babbles live: the `Mixer` runs inside an AVAudioSourceNode. `say` is called from the main thread.
final class Speaker: @unchecked Sendable {
    static let shared = Speaker()

    let sampleRate: Double
    private let engine = AVAudioEngine()
    private let inbox = OSAllocatedUnfairLock(initialState: [Mixer.Voice]())
    private var mixer = Mixer() // audio thread only

    private init() {
        let session = AVAudioSession.sharedInstance()
        // Ambient: respects the silent switch and mixes with the user's music.
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)
        sampleRate = session.sampleRate > 0 ? session.sampleRate : 44_100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let source = AVAudioSourceNode(format: format) { [unowned self] _, _, frames, buffers in
            self.render(Int(frames), UnsafeMutableAudioBufferListPointer(buffers))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try? engine.start()
        // Route and format changes stop the engine; start it again.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let engine = self?.engine, !engine.isRunning else { return }
            try? engine.start()
        }
    }

    func say(_ text: String, voice: VoiceParams, id: Int) {
        guard Settings.voice else { return } // «Voz» off: the bubble still writes itself, silently
        let babble = Babble(text, voice: voice, sampleRate: sampleRate)
        inbox.withLock { $0.append(Mixer.Voice(id: id, babble: babble)) }
        if !engine.isRunning { try? engine.start() }
    }

    private func render(_ frames: Int, _ buffers: UnsafeMutableAudioBufferListPointer) {
        let fresh = inbox.withLockIfAvailable { (q: inout [Mixer.Voice]) -> [Mixer.Voice] in
            defer { q.removeAll() }
            return q
        }
        for v in fresh ?? [] { mixer.add(v.babble, id: v.id) }
        guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        for n in 0..<frames { out[n] = mixer.next() * 0.6 }
    }
}

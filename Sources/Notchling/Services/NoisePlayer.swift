import AVFoundation

/// Procedural background sounds. No audio files ship with the app.
final class NoisePlayer {
    enum Sound: String, CaseIterable, Identifiable {
        case off, brown, pink, white, ocean
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let state = NoiseState()

    var volume: Float = 0.5 { didSet { engine.mainMixerNode.outputVolume = volume } }

    func play(_ sound: Sound) {
        stop()
        guard sound != .off else { return }
        state.sound = sound
        let format = engine.outputNode.inputFormat(forBus: 0)
        state.sampleRate = format.sampleRate
        let state = self.state
        let node = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let s = state.next()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                }
            }
            return noErr
        }
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = volume
        self.node = node
        try? engine.start()
    }

    func stop() {
        engine.stop()
        if let node {
            engine.detach(node)
            self.node = nil
        }
    }
}

/// Generator state lives on the audio thread; only `sound` is set from main before start.
private final class NoiseState {
    var sound: NoisePlayer.Sound = .brown
    var sampleRate: Double = 44_100
    private var brown: Float = 0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var phase: Double = 0

    func next() -> Float {
        let white = Float.random(in: -1...1)
        switch sound {
        case .off: return 0
        case .white: return white * 0.25
        case .brown:
            return nextBrown(white)
        case .pink:
            // Paul Kellet's refined pink filter.
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return pink * 0.08
        case .ocean:
            // Brown noise swelling on a slow ~9 s wave.
            phase += 1 / sampleRate
            let swell = Float(0.25 + 0.75 * pow(0.5 + 0.5 * sin(2 * .pi * phase / 9), 2))
            return nextBrown(white) * swell
        }
    }

    private func nextBrown(_ white: Float) -> Float {
        brown = (brown + 0.02 * white) / 1.02
        return brown * 3.0
    }
}

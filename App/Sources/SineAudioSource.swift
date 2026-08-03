import Foundation
import CProjectM

// Placeholder signal until real system audio arrives: a 220 Hz sine with a slow
// amplitude pulse, pushed once per rendered frame.
struct SineAudioSource {
    private let sampleRate: Float = 44100
    private let framesPerPump: Int
    private var buffer: [Float]
    private var phase: Float = 0
    private var pulsePhase: Float = 0

    init(fps: Int = 30) {
        framesPerPump = min(Int(44100) / fps, Int(projectm_pcm_get_max_samples()))
        buffer = [Float](repeating: 0, count: framesPerPump * 2)
    }

    mutating func pump(into handle: projectm_handle) {
        let amplitude = 0.45 + 0.35 * sin(pulsePhase)
        for frame in 0..<framesPerPump {
            let sample = amplitude * sin(phase)
            buffer[frame * 2] = sample
            buffer[frame * 2 + 1] = sample
            phase += 2 * .pi * 220 / sampleRate
        }
        phase = phase.truncatingRemainder(dividingBy: 2 * .pi)
        pulsePhase += 2 * .pi * 0.4 * Float(framesPerPump) / sampleRate
        pulsePhase = pulsePhase.truncatingRemainder(dividingBy: 2 * .pi)
        projectm_pcm_add_float(handle, buffer, UInt32(framesPerPump), PROJECTM_STEREO)
    }
}

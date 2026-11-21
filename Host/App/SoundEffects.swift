import AVFoundation
import Foundation

/// Procedurally synthesized UI sounds for Dialup.
///
/// Every sound is generated in code (sines, filtered noise, envelopes) — there are
/// no bundled or sampled recordings. Buffers are synthesized once and cached.
/// Playback goes through a single lazily-started `AVAudioEngine` with a small pool
/// of player nodes for overlapping short sounds plus a dedicated node for the modem.
@MainActor final class SoundEffects {
    static let shared = SoundEffects()

    enum Sound: String, CaseIterable, Sendable {
        case click, complete, error, ding, modem
    }

    /// Posted when `isEnabled` changes, so every window can tell its chrome (`sounds` event).
    static let didChange = Notification.Name("DialupSoundsDidChange")
    private static let defaultsKey = "SoundsEnabled"
    nonisolated private static let sampleRate: Double = 44_100
    private static let masterVolume: Float = 0.25
    /// The modem sits a bit lower than the UI blips.
    private static let modemVolume: Float = 0.7
    /// Player nodes for overlapping short sounds.
    private static let poolSize = 3

    /// Persisted in UserDefaults ("SoundsEnabled"), defaults to true.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            if !newValue { stopModem() }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    // MARK: - Engine state

    private var engine: AVAudioEngine?
    private var pool: [AVAudioPlayerNode] = []
    private var modemNode: AVAudioPlayerNode?
    private var nextPoolIndex = 0
    private var engineFailed = false
    private var cache: [Sound: AVAudioPCMBuffer] = [:]
    /// Bumped on every modem play/stop so a late async synthesis doesn't start
    /// playing after the caller already asked us to stop.
    private var modemToken = 0

    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)

    private init() {}

    // MARK: - Public API

    /// Plays a sound without blocking. No-op when disabled or audio is unavailable.
    func play(_ sound: Sound) {
        guard isEnabled else { return }
        if sound == .modem { playModem(); return }
        guard let buffer = buffer(for: sound), let node = nextPoolNode() else { return }
        schedule(buffer, on: node)
    }

    /// Stops a playing (or pending) modem sound.
    func stopModem() {
        modemToken += 1
        modemNode?.stop()
    }

    // MARK: - Playback plumbing

    private func playModem() {
        modemToken += 1
        let token = modemToken
        if let cached = cache[.modem] {
            startModem(cached)
            return
        }
        // The modem is ~7 s of audio; synthesize it off the main actor. Only the
        // Sendable [Float] crosses the boundary; the buffer is built back here.
        Task { [weak self] in
            let samples = await Task.detached(priority: .userInitiated) {
                SoundEffects.synthesize(.modem)
            }.value
            guard let self, let buffer = self.makeBuffer(samples) else { return }
            self.cache[.modem] = buffer
            if token == self.modemToken, self.isEnabled { self.startModem(buffer) }
        }
    }

    private func startModem(_ buffer: AVAudioPCMBuffer) {
        guard ensureEngine(), let node = modemNode else { return }
        schedule(buffer, on: node)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode) {
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    private func nextPoolNode() -> AVAudioPlayerNode? {
        guard ensureEngine(), !pool.isEmpty else { return nil }
        // Prefer an idle node; otherwise round-robin (interrupting the oldest).
        if let idle = pool.first(where: { !$0.isPlaying }) { return idle }
        defer { nextPoolIndex = (nextPoolIndex + 1) % pool.count }
        return pool[nextPoolIndex]
    }

    /// Builds the engine on first use and (re)starts it if needed. Returns false
    /// if audio is unavailable; we then silently skip playback.
    private func ensureEngine() -> Bool {
        guard !engineFailed, let format else { return false }
        if engine == nil {
            let e = AVAudioEngine()
            let nodes = (0..<Self.poolSize).map { _ in AVAudioPlayerNode() }
            let modem = AVAudioPlayerNode()
            for node in nodes + [modem] {
                e.attach(node)
                e.connect(node, to: e.mainMixerNode, format: format)
            }
            modem.volume = Self.modemVolume
            e.mainMixerNode.outputVolume = Self.masterVolume
            e.prepare()
            engine = e; pool = nodes; modemNode = modem
        }
        guard let engine else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start() // also recovers after a device/configuration change
            return true
        } catch {
            NSLog("SoundEffects: audio engine unavailable: \(error)")
            engineFailed = true
            return false
        }
    }

    private func buffer(for sound: Sound) -> AVAudioPCMBuffer? {
        if let cached = cache[sound] { return cached }
        let buffer = makeBuffer(Self.synthesize(sound))
        cache[sound] = buffer
        return buffer
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format, !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buf.floatChannelData?[0] else { return nil }
        // baseAddress is non-nil: `samples` was checked to be non-empty above.
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buf.frameLength = AVAudioFrameCount(samples.count)
        return buf
    }

    // MARK: - Synthesis (pure, nonisolated)

    nonisolated private static func synthesize(_ sound: Sound) -> [Float] {
        var s = Synth(sampleRate: sampleRate)
        switch sound {
        case .click:
            // A ~25 ms tick: band-passed noise burst plus a tiny damped 2.4 kHz ping.
            s.noise(at: 0, dur: 0.025, amp: 0.55, center: 3200, q: 1.2, attack: 0.0008, decayRate: 220)
            s.tone(at: 0, dur: 0.02, freqs: [2400], amp: 0.12, attack: 0.0005, decayRate: 300)
        case .complete:
            // Gentle rising chime: G5 then C6, each with a soft attack and exp decay.
            s.tone(at: 0.00, dur: 0.16, freqs: [784, 1568], amp: 0.35, attack: 0.008, decayRate: 18, partialGain: 0.2)
            s.tone(at: 0.09, dur: 0.16, freqs: [1047, 2094], amp: 0.35, attack: 0.008, decayRate: 18, partialGain: 0.2)
        case .error:
            // Low "bonk": two detuned low tones with a fast decay and a short pitch drop.
            s.tone(at: 0, dur: 0.18, freqs: [180], amp: 0.5, attack: 0.003, decayRate: 22, glide: -0.25)
            s.tone(at: 0, dur: 0.18, freqs: [191], amp: 0.4, attack: 0.003, decayRate: 25, glide: -0.25)
        case .ding:
            // Soft bell: fundamental plus inharmonic partials decaying at different rates.
            s.tone(at: 0, dur: 0.4, freqs: [1320], amp: 0.4, attack: 0.002, decayRate: 9)
            s.tone(at: 0, dur: 0.3, freqs: [1320 * 2.76], amp: 0.08, attack: 0.002, decayRate: 18)
            s.tone(at: 0, dur: 0.2, freqs: [1320 * 5.4], amp: 0.03, attack: 0.001, decayRate: 30)
        case .modem:
            modem(&s)
        }
        return s.samples
    }

    /// An original impression of a 56k handshake (~7.2 s).
    nonisolated private static func modem(_ s: inout Synth) {
        // 1. DTMF dialing: standard row/column frequency pairs, 80 ms tones, 70 ms gaps.
        let dtmf: [Character: (Double, Double)] = [
            "1": (697, 1209), "2": (697, 1336), "3": (697, 1477),
            "4": (770, 1209), "5": (770, 1336), "6": (770, 1477),
            "7": (852, 1209), "8": (852, 1336), "9": (852, 1477), "0": (941, 1336),
        ]
        var t = 0.15
        for digit in "5550173" {
            if let (lo, hi) = dtmf[digit] {
                s.tone(at: t, dur: 0.08, freqs: [lo, hi], amp: 0.3, attack: 0.003, release: 0.005)
            }
            t += 0.15
        }
        // 2. Ring-back (440 + 480 Hz), one shortened ring.
        t += 0.25
        s.tone(at: t, dur: 0.9, freqs: [440, 480], amp: 0.22, attack: 0.02, release: 0.03)
        t += 1.1
        // 3. Answer tone ~2100 Hz with phase reversals every 450 ms (the audible "tick").
        s.tone(at: t, dur: 1.2, freqs: [2100], amp: 0.25, attack: 0.01, release: 0.02, phaseFlip: 0.45)
        t += 1.3
        // 4. Warbling probes: fast alternation and upward chirps.
        for i in 0..<6 {
            let f = i.isMultiple(of: 2) ? 1200.0 : 2400.0
            s.tone(at: t + Double(i) * 0.05, dur: 0.05, freqs: [f], amp: 0.2, attack: 0.002, release: 0.004)
        }
        t += 0.32
        s.tone(at: t, dur: 0.25, freqs: [600], amp: 0.2, attack: 0.005, release: 0.02, glide: 3.0)
        t += 0.27
        // 5. Static bursts at different pitches, layered with a wobbling carrier.
        let bursts: [(dur: Double, center: Double, q: Double)] = [
            (0.22, 1800, 3), (0.18, 900, 2), (0.30, 2600, 4), (0.16, 1400, 1.5), (0.35, 3200, 2.5), (0.28, 2000, 1),
        ]
        for b in bursts {
            s.noise(at: t, dur: b.dur, amp: 0.35, center: b.center, q: b.q, attack: 0.004, release: 0.01)
            s.tone(at: t, dur: b.dur, freqs: [b.center * 0.75], amp: 0.06, attack: 0.004, release: 0.01, vibrato: (18, 40))
            t += b.dur + 0.02
        }
        // 6. Settling hiss that fades out.
        s.noise(at: t, dur: 1.4, amp: 0.25, center: 4000, q: 0.7, attack: 0.02, release: 1.3)
    }
}

/// Minimal additive synthesizer writing into a mono Float buffer that grows as needed.
private struct Synth {
    let sampleRate: Double
    var samples: [Float] = []
    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15 // deterministic xorshift seed

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// Envelope: linear attack, then either exponential decay (`decayRate`, 1/s) or
    /// a linear `release` at the end of the segment.
    private func envelope(_ x: Double, dur: Double, attack: Double, release: Double, decayRate: Double) -> Double {
        var e = attack > 0 ? min(1, x / attack) : 1
        if decayRate > 0 { e *= exp(-decayRate * max(0, x - attack)) }
        if release > 0, x > dur - release { e *= max(0, (dur - x) / release) }
        return e
    }

    private mutating func ensure(_ count: Int) {
        if samples.count < count { samples.append(contentsOf: repeatElement(0, count: count - samples.count)) }
    }

    /// Sum of sines. `glide` bends pitch by that fraction over the duration,
    /// `phaseFlip` inverts phase every N seconds, `vibrato` is (rate Hz, depth Hz).
    mutating func tone(at start: Double, dur: Double, freqs: [Double], amp: Double,
                       attack: Double, release: Double = 0, decayRate: Double = 0,
                       partialGain: Double = 1, glide: Double = 0, phaseFlip: Double = 0,
                       vibrato: (Double, Double) = (0, 0)) {
        let first = Int(start * sampleRate), n = Int(dur * sampleRate)
        ensure(first + n)
        var phases = [Double](repeating: 0, count: freqs.count)
        for i in 0..<n {
            let x = Double(i) / sampleRate
            let bend = 1 + glide * (x / dur) + vibrato.1 / max(1, freqs[0]) * sin(2 * .pi * vibrato.0 * x)
            var v = 0.0
            for (k, f) in freqs.enumerated() {
                phases[k] += 2 * .pi * f * bend / sampleRate
                v += sin(phases[k]) * (k == 0 ? 1 : partialGain)
            }
            if phaseFlip > 0, Int(x / phaseFlip) % 2 == 1 { v = -v }
            let e = envelope(x, dur: dur, attack: attack, release: release, decayRate: decayRate)
            samples[first + i] += Float(v / Double(freqs.count) * amp * e)
        }
    }

    /// White noise through a state-variable band-pass filter (Chamberlin SVF).
    mutating func noise(at start: Double, dur: Double, amp: Double, center: Double, q: Double,
                        attack: Double, release: Double = 0, decayRate: Double = 0) {
        let first = Int(start * sampleRate), n = Int(dur * sampleRate)
        ensure(first + n)
        let f = 2 * sin(.pi * min(center, sampleRate / 6) / sampleRate)
        let damp = 1 / max(0.5, q)
        var low = 0.0, band = 0.0
        for i in 0..<n {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let white = Double(rng >> 11) / Double(1 << 53) * 2 - 1
            low += f * band
            let high = white - low - damp * band
            band += f * high
            let e = envelope(Double(i) / sampleRate, dur: dur, attack: attack, release: release, decayRate: decayRate)
            samples[first + i] += Float(band * amp * e)
        }
    }
}

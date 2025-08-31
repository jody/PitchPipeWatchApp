import SwiftUI
import AVFoundation
import WatchKit

// MARK: - Tone Generator (looping WAV via AVAudioPlayer)
final class ToneGenerator {
    private var player: AVAudioPlayer?
    private var sampleRate: Double = 44100.0

    var frequency: Double = 440 { didSet { rebuildIfPlayingOrNext() } }
    var amplitude: Float  = 0.45 { didSet { rebuildIfPlayingOrNext() } }

    private var wavData: Data?

    init() {
        buildWav()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)

        if wavData == nil { buildWav() }
        guard let data = wavData else { throw NSError(domain: "ToneGen", code: -1) }

        player = try AVAudioPlayer(data: data)
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Internals
    private func rebuildIfPlayingOrNext() {
        let wasPlaying = player?.isPlaying == true
        if wasPlaying { player?.stop() }
        buildWav()
        if wasPlaying {
            do { try start() } catch { print("Restart after rebuild failed:", error) }
        }
    }

    private func buildWav() {
        wavData = makeWavData(frequency: frequency, amplitude: amplitude, duration: 0.35, sampleRate: Int(sampleRate))
    }

    // Minimal WAV writer for mono Float32 PCM (warning-free)
    private func makeWavData(frequency: Double, amplitude: Float, duration: Double, sampleRate: Int) -> Data? {
        let frameCount = Int(Double(sampleRate) * duration)
        var samples = [Float](repeating: 0, count: frameCount)
        let twoPi = 2.0 * Double.pi
        let step = twoPi * frequency / Double(sampleRate)
        var phase = 0.0
        for i in 0..<frameCount {
            samples[i] = Float(sin(phase)) * amplitude
            phase += step
            if phase > twoPi { phase -= twoPi }
        }

        func append32(_ v: UInt32, to data: inout Data) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { raw in data.append(Data(raw)) }
        }
        func append16(_ v: UInt16, to data: inout Data) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { raw in data.append(Data(raw)) }
        }

        var data = Data()
        let pcmData = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let subchunk2Size = UInt32(pcmData.count)
        let byteRate = sampleRate * 4 * 1

        data.append(contentsOf: "RIFF".utf8)
        append32(36 + subchunk2Size, to: &data)
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        append32(16, to: &data)
        append16(3, to: &data)                 // float32
        append16(1, to: &data)                 // mono
        append32(UInt32(sampleRate), to: &data)
        append32(UInt32(byteRate), to: &data)
        append16(4, to: &data)
        append16(32, to: &data)

        data.append(contentsOf: "data".utf8)
        append32(subchunk2Size, to: &data)
        data.append(pcmData)
        return data
    }
}

// MARK: - Watch UI
struct ContentView: View {
    @State private var gen = ToneGenerator()
    @State private var isPlaying = false
    @State private var frequency: Double = 440
    @State private var amplitude: Double = 0.45
    @State private var showAdvanced = false

    // Common vocal reference notes; adjust as you like
    private let noteOptions: [(name: String, freq: Double)] = [
        ("C4", 261.63), ("D4", 293.66), ("E4", 329.63),
        ("F4", 349.23), ("G4", 392.00), ("A4", 440.00), ("B4", 493.88),
        ("C5", 523.25)
    ]

    // Adaptive grid for circular note buttons
    private let grid = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            // Scrollable content area
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    // Header row: title + advanced toggle
                    HStack {
                        Text("Pitch Pipe").font(.headline)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdvanced.toggle()
                            }
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Toggle advanced controls")
                    }

                    // Current frequency readout
                    Text("\(Int(frequency)) Hz")
                        .font(.title3)
                        .monospacedDigit()

                    // Note buttons as round, watch-like controls
                    LazyVGrid(columns: grid, spacing: 8) {
                        ForEach(noteOptions, id: \.name) { note in
                            Button {
                                frequency = note.freq
                                gen.frequency = note.freq
                                if !isPlaying {
                                    do { try gen.start(); isPlaying = true } catch { print("start failed:", error) }
                                }
                                WKInterfaceDevice.current().play(.click)
                            } label: {
                                Text(note.name)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.accentColor))
                                    .foregroundColor(.white)
                                    .font(.caption.bold())
                            }
                            .accessibilityLabel("Set note \(note.name)")
                        }
                    }
                    .padding(.top, 2)

                    // Advanced (hidden by default)
                    if showAdvanced {
                        VStack(spacing: 10) {
                            // Frequency slider
                            VStack(spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { frequency },
                                        set: { newVal in
                                            frequency = newVal
                                            gen.frequency = newVal
                                        }),
                                    in: 110...880, step: 1
                                )
                                .focusable(true) // use Digital Crown
                                Text("Frequency (crown)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            // Volume slider
                            VStack(spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { amplitude },
                                        set: { newVal in
                                            amplitude = newVal
                                            gen.amplitude = Float(newVal)
                                        }),
                                    in: 0.10...0.60, step: 0.01
                                )
                                .focusable(true)
                                Text("Volume")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }

            Spacer(minLength: 6) // pushes Play/Stop to bottom

            // Full-width capsule Play/Stop anchored at bottom
            Button {
                if isPlaying {
                    gen.stop()
                    isPlaying = false
                } else {
                    gen.frequency = frequency
                    gen.amplitude = Float(amplitude)
                    do { try gen.start(); isPlaying = true } catch { print("Audio start failed:", error) }
                }
                WKInterfaceDevice.current().play(.click)
            } label: {
                Text(isPlaying ? "Stop" : "Play")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(isPlaying ? Color.red : Color.green)
                    )
                    .foregroundColor(.white)
                    .font(.body.bold())
            }
            .buttonStyle(.plain) // we’re styling manually
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onDisappear {
            if isPlaying { gen.stop(); isPlaying = false }
        }
    }
}

//
//  AudioCapture.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AVFoundation

/// Captures microphone audio using AVAudioEngine
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "com.voicedock.audio.processing")
    private let lock = NSLock()

    private var audioBuffer: [Float] = []
    private var isRecording = false

    init() {
        configureSession()
        installTap()
    }

    private func configureSession() {
        // macOS doesn't support AVAudioSession configuration like iOS
        // Audio setup is handled automatically by AVAudioEngine on macOS
        print("Audio session configured for macOS")
    }

    private func installTap() {
        let input = engine.inputNode
        // Request 16 kHz mono Float32 format for ASR compatibility
        let channelLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)!
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            interleaved: false,
            channelLayout: channelLayout
        )
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.lock.lock()
            let recording = self.isRecording
            self.lock.unlock()
            guard recording else { return }
            self.process(buffer: buffer)
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        audioBuffer.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
    }

    func start() {
        lock.lock()
        isRecording = true
        audioBuffer.removeAll()
        lock.unlock()
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stop() -> [Float] {
        lock.lock()
        isRecording = false
        lock.unlock()
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return audioBuffer
    }

    func cancel() {
        lock.lock()
        isRecording = false
        audioBuffer.removeAll()
        lock.unlock()
        engine.stop()
    }
}
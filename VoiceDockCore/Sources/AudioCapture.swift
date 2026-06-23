//
//  AudioCapture.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.core", category: "AudioCapture")

/// Protocol for audio capture abstraction
public protocol AudioCaptureProtocol {
    func start() throws
    func stop() -> [Float]
    func cancel()
}

/// Captures microphone audio using AVAudioEngine at 16 kHz mono Float32.
public final class AudioCapture: AudioCaptureProtocol {
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var audioBuffer: [Float] = []
    private var isRecording = false
    private var tapInstalled = false

    public init() {
        // Defer tap installation to first start() call
    }

    private func ensureTapInstalled() {
        guard !tapInstalled else { return }
        tapInstalled = true

        let input = engine.inputNode
        let channelLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)!
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            interleaved: false,
            channelLayout: channelLayout
        )
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Fast path: do not hold NSLock on the audio callback longer than 1 read.
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
        let snapshot = Array(UnsafeBufferPointer(start: samples, count: count))

        lock.lock()
        audioBuffer.append(contentsOf: snapshot)
        lock.unlock()
    }

    public func start() throws {
        ensureTapInstalled()
        lock.lock()
        guard !isRecording else {
            lock.unlock()
            return
        }
        isRecording = true
        audioBuffer.removeAll()
        lock.unlock()
        do {
            try engine.start()
            logger.info("Audio engine started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            lock.lock()
            isRecording = false
            audioBuffer.removeAll()
            lock.unlock()
            throw VoiceDockError.audioEngineStartFailed
        }
    }

    public func stop() -> [Float] {
        logger.info("AudioCapture.stop() called")
        lock.lock()
        isRecording = false
        lock.unlock()
        logger.info("AudioEngine stopping...")
        engine.stop()
        logger.info("AudioEngine stopped")
        lock.lock()
        let captured = self.audioBuffer
        audioBuffer.removeAll()
        logger.info("AudioCapture.stop() returning \(captured.count) samples")
        defer { lock.unlock() }
        return captured
    }

    public func cancel() {
        lock.lock()
        isRecording = false
        audioBuffer.removeAll()
        lock.unlock()
        engine.stop()
        logger.info("Audio engine cancelled")
    }
}

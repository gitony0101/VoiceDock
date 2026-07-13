import Foundation
import AVFoundation
import VoiceDockCore
import os.log

private let recorderLogger = Logger(subsystem: "com.voicedock.bench", category: "FixtureRecorder")

/// Records microphone audio and saves as PCM WAV file
public final class FixtureRecorder {
    private let engine = AVAudioEngine()
    private let normalizer = AudioNormalizer()
    private let lock = NSLock()

    private var audioBuffer: [Float] = []
    private var isRecording = false
    private var tapInstalled = false
    private var startTime: Date?
    private var maxDuration: Double = 30.0  // Default max duration

    public init(maxDuration: Double = 30.0) {
        self.maxDuration = maxDuration
    }

    private func ensureTapInstalled() {
        guard !tapInstalled else { return }
        tapInstalled = true

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.lock.lock()
            let recording = self.isRecording
            let needsProcess = recording
            self.lock.unlock()
            guard needsProcess else { return }
            self.process(buffer: buffer)
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let snapshot = normalizer.normalize(buffer: buffer), !snapshot.isEmpty else { return }

        lock.lock()
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let shouldContinue = isRecording && elapsed < maxDuration
        if shouldContinue {
            audioBuffer.append(contentsOf: snapshot)
        } else if isRecording && elapsed >= maxDuration {
            // Auto-stop when max duration reached
            isRecording = false
            startTime = nil
            recorderLogger.info("Auto-stopped recording at max duration (\(self.maxDuration)s)")
        }
        lock.unlock()
    }

    /// Start recording audio
    public func start() throws {
        ensureTapInstalled()

        lock.lock()
        guard !isRecording else {
            lock.unlock()
            throw RecordingError.alreadyRecording
        }

        isRecording = true
        audioBuffer.removeAll()
        startTime = Date()
        let maxDur = maxDuration
        lock.unlock()

        recorderLogger.info("Recording started (max duration: \(String(format: "%.1f", maxDur))s)")

        do {
            try engine.start()
            recorderLogger.info("Recording started")
        } catch {
            lock.lock()
            isRecording = false
            audioBuffer.removeAll()
            startTime = nil
            lock.unlock()
            throw RecordingError.engineStartFailed(error.localizedDescription)
        }
    }

    /// Stop recording and return the captured audio
    public func stop() throws -> ([Float], Double) {
        recorderLogger.info("FixtureRecorder.stop() called")

        lock.lock()
        isRecording = false
        let captured = self.audioBuffer
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        audioBuffer.removeAll()
        startTime = nil
        lock.unlock()

        engine.stop()

        // Calculate statistics
        let stats = calculateStatistics(for: captured)

        recorderLogger.info("Recording stopped: \(captured.count) samples, \(String(format: "%.2f", duration))s duration, min=\(String(format: "%.4f", stats.min)), max=\(String(format: "%.4f", stats.max)), rms=\(String(format: "%.4f", stats.rms))")

        return (captured, duration)
    }

    /// Cancel recording without saving
    public func cancel() {
        lock.lock()
        isRecording = false
        audioBuffer.removeAll()
        startTime = nil
        lock.unlock()
        engine.stop()
        recorderLogger.info("Recording cancelled")
    }

    /// Save audio samples as PCM WAV file
    public func saveAsWAV(_ samples: [Float], to url: URL, force: Bool = false) throws {
        guard !samples.isEmpty else {
            throw RecordingError.noAudioCaptured
        }

        // Check if file exists and force flag
        if FileManager.default.fileExists(atPath: url.path) && !force {
            throw RecordingError.fileExists(url.path)
        }

        // Create parent directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Remove existing file if force
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Validate audio format: should be 16 kHz mono Float32
        let expectedSampleRate: Double = 16_000
        let duration = Double(samples.count) / expectedSampleRate
        recorderLogger.info("Audio validation: \(samples.count) samples, \(String(format: "%.2f", duration))s at 16 kHz mono Float32")

        // WAV file format: 16 kHz mono PCM Float32
        let sampleRate: Double = 16_000
        let channels: AVAudioChannelCount = 1
        let bitsPerSample = 32  // Float32

        let dataByteSize = samples.count * MemoryLayout<Float>.stride
        let blockAlign = Int(channels) * bitsPerSample / 8
        let byteRate = Int(sampleRate) * blockAlign

        var wavData = Data()

        // RIFF header
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        let riffSize = 36 + dataByteSize
        wavData.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        wavData.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let fmtChunkSize = 16
        wavData.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Data($0) })
        let audioFormat: UInt16 = 3  // IEEE Float32
        wavData.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Data($0) })

        // data chunk
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataByteSize).littleEndian) { Data($0) })

        // Convert Float32 samples to bytes
        for sample in samples {
            var sampleBytes = sample
            wavData.append(contentsOf: Data(bytes: &sampleBytes, count: MemoryLayout<Float>.stride))
        }

        try wavData.write(to: url)
        recorderLogger.info("WAV file saved: \(url.path) (\(dataByteSize) bytes)")
    }

    /// Calculate audio statistics
    public func calculateStatistics(for samples: [Float]) -> AudioStatistics {
        guard !samples.isEmpty else {
            return AudioStatistics(sampleCount: 0, min: 0, max: 0, rms: 0)
        }

        var minVal: Float = .infinity
        var maxVal: Float = -.infinity
        var sumSquares: Float = 0

        for sample in samples {
            if sample < minVal { minVal = sample }
            if sample > maxVal { maxVal = sample }
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(samples.count))

        return AudioStatistics(
            sampleCount: samples.count,
            min: minVal,
            max: maxVal,
            rms: rms
        )
    }
}

public struct AudioStatistics {
    public let sampleCount: Int
    public let min: Float
    public let max: Float
    public let rms: Float
}

public enum RecordingError: LocalizedError {
    case alreadyRecording
    case engineStartFailed(String)
    case noAudioCaptured
    case fileExists(String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording. Stop current recording first."
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .noAudioCaptured:
            return "No audio was captured"
        case .fileExists(let path):
            return "File already exists at \(path). Use --force to overwrite."
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}
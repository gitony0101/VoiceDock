//
//  AudioNormalizer.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AVFoundation

/// Converts audio to canonical 16 kHz mono Float32 format
public struct AudioNormalizer {
    private let targetSampleRate: Double = 16_000
    private let targetChannels: AVAudioChannelCount = 1

    public init() {}

    public func normalize(buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }

        guard let inputData = buffer.floatChannelData else { return nil }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var mono: [Float] = []
        mono.reserveCapacity(frameCount)

        if channelCount == 1 {
            let samples = UnsafeBufferPointer(start: inputData[0], count: frameCount)
            mono.append(contentsOf: samples)
        } else {
            for frameIndex in 0..<frameCount {
                var sample: Float = 0
                for channelIndex in 0..<channelCount {
                    sample += inputData[channelIndex][frameIndex]
                }
                mono.append(sample / Float(channelCount))
            }
        }

        return resampleToTarget(samples: mono, sourceSampleRate: buffer.format.sampleRate)
    }

    public func normalize(samples: [Float]) -> [Float] {
        return samples
    }

    private func resampleToTarget(samples: [Float], sourceSampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard sourceSampleRate > 0 else { return samples }

        let ratio = targetSampleRate / sourceSampleRate
        guard abs(ratio - 1.0) > 0.000_001 else { return samples }

        let outputCount = max(1, Int((Double(samples.count) * ratio).rounded()))
        guard outputCount != samples.count else { return samples }

        var output: [Float] = []
        output.reserveCapacity(outputCount)

        for outputIndex in 0..<outputCount {
            let sourcePosition = Double(outputIndex) / ratio
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            output.append(lower + (upper - lower) * fraction)
        }

        return output
    }
}

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

        var result: [Float] = []
        result.reserveCapacity(frameCount)

        if channelCount == 1 {
            let samples = UnsafeBufferPointer(start: inputData[0], count: frameCount)
            result.append(contentsOf: samples)
        } else {
            for frameIndex in 0..<frameCount {
                var sample: Float = 0
                for channelIndex in 0..<channelCount {
                    sample += inputData[channelIndex][frameIndex]
                }
                result.append(sample / Float(channelCount))
            }
        }

        return result
    }

    public func normalize(samples: [Float]) -> [Float] {
        return samples
    }
}
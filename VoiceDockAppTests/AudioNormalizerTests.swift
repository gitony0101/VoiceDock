//
//  AudioNormalizerTests.swift
//  VoiceDockAppTests
//
//  VoiceDock Push-to-Talk MVP
//

import XCTest
import AVFoundation
@testable import VoiceDockCore

final class AudioNormalizerTests: XCTestCase {
    var sut: AudioNormalizer!

    override func setUp() {
        super.setUp()
        sut = AudioNormalizer()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testNormalizeSamplesPassthrough() {
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let result = sut.normalize(samples: samples)
        XCTAssertEqual(result, samples, "Samples normalize should pass through")
    }

    func testNormalizeEmptyBufferReturnsNil() {
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!,
            frameCapacity: 0
        )!
        buffer.frameLength = 0

        let result = sut.normalize(buffer: buffer)
        XCTAssertNil(result, "Empty buffer should return nil")
    }

    func testNormalizeMonoBufferPreservesSamples() {
        let sampleRate: Double = 44100
        let frameCount: AVAudioFrameCount = 10
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!,
            frameCapacity: frameCount
        )!

        // Fill buffer with test samples
        let channelData = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            channelData[i] = Float(i) * 0.1
        }
        buffer.frameLength = frameCount

        let result = sut.normalize(buffer: buffer)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, Int(frameCount), "Should preserve sample count")
    }

    func testNormalizeStereoBufferDownmix() {
        let sampleRate: Double = 44100
        let frameCount: AVAudioFrameCount = 10
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!,
            frameCapacity: frameCount
        )!

        // Fill left channel with 0.5, right channel with 0.3
        let leftData = buffer.floatChannelData![0]
        let rightData = buffer.floatChannelData![1]
        for i in 0..<Int(frameCount) {
            leftData[i] = 0.5
            rightData[i] = 0.3
        }
        buffer.frameLength = frameCount

        let result = sut.normalize(buffer: buffer)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, Int(frameCount), "Should preserve sample count")
        // Downmixed value should be (0.5 + 0.3) / 2 = 0.4
        let firstSample = result?[0] ?? 0
        XCTAssertEqual(firstSample, 0.4, accuracy: 0.001, "Should downmix stereo to mono")
    }
}
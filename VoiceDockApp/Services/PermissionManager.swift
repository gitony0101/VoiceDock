//
//  PermissionManager.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import AVFoundation

/// Manages microphone and Accessibility permissions
struct PermissionManager {
    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
    }

    func checkMicrophone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestMicrophone() async -> PermissionStatus {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    func checkAccessibility() -> PermissionStatus {
        if AXIsProcessTrusted() {
            return .granted
        } else {
            return .notDetermined
        }
    }

    func requestAccessibility() {
        // Accessibility permission request - uses Carbon constant
        let options: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
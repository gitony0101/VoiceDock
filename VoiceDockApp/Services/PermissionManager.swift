//
//  PermissionManager.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.voicedock.app", category: "PermissionManager")

/// String form of kAXTrustedCheckOptionPrompt. Accessibility framework
/// matches keys by CFString contents, so a String of the same contents
/// is sufficient and avoids Swift 6 shared-state warnings.
private let axPromptKey = "AXTrustedCheckOptionPrompt"

struct PermissionManager {
    enum PermissionStatus: Equatable {
        case granted
        case denied
        case notDetermined
    }

    func checkMicrophone() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let mapped: PermissionStatus
        switch status {
        case .authorized: mapped = .granted
        case .denied, .restricted: mapped = .denied
        case .notDetermined: mapped = .notDetermined
        @unknown default: mapped = .notDetermined
        }
        logger.info("Microphone status: raw=\(status.rawValue) mapped=\(String(describing: mapped))")
        return mapped
    }

    @available(macOS, deprecated: 14.0)
    func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let result: PermissionStatus = granted ? .granted : .denied
        logger.info("Microphone request result: \(String(describing: result))")
        return result
    }

    func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        logger.info("Accessibility trust state: \(trusted)")
        return trusted
    }

    /// Prompts the user to grant Accessibility permission if needed.
    @MainActor
    func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            logger.info("Accessibility already trusted")
            return true
        }
        logger.info("Requesting Accessibility permission")
        let options = [axPromptKey: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility request OSStatus=\(result)")
        return result
    }

    // P1-1 Fix: Poll for Accessibility permission with timeout
    // Returns true if granted within timeout, false otherwise
    @MainActor
    public func ensureAccessibilityPermission(timeoutSeconds: Int = 30) async -> Bool {
        // Immediate check
        if AXIsProcessTrusted() {
            logger.info("Accessibility already trusted")
            return true
        }

        // Prompt user
        _ = requestAccessibilityIfNeeded()

        // Poll for permission grant (user may take time in System Settings)
        logger.info("Polling for Accessibility permission (timeout: \(timeoutSeconds)s)...")
        for _ in 0..<timeoutSeconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
            if AXIsProcessTrusted() {
                logger.info("Accessibility granted after polling")
                return true
            }
        }

        logger.warning("Accessibility not granted within \(timeoutSeconds) seconds")
        return false
    }
}
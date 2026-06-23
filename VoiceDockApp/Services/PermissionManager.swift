//
//  PermissionManager.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import AVFoundation
import os.log
import Security

private let logger = Logger(subsystem: "com.voicedock.app", category: "PermissionManager")
private let permissionDiagnosticsPath = "/tmp/voicedock-permission-diagnostics.log"

/// String form of kAXTrustedCheckOptionPrompt. Accessibility framework
/// matches keys by CFString contents, so a String of the same contents
/// is sufficient and avoids Swift 6 shared-state warnings.
private let axPromptKey = "AXTrustedCheckOptionPrompt"

@MainActor
protocol PermissionStatusProviding {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus
    func requestMicrophoneAccess() async -> Bool
    func isAccessibilityTrusted() -> Bool
    func requestAccessibilityPrompt() -> Bool
}

struct SystemPermissionStatusProvider: PermissionStatusProviding {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPrompt() -> Bool {
        let options = [axPromptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// Observable permission manager that publishes live permission state changes.
///
/// P1 Fix: This class now conforms to ObservableObject so that SwiftUI views
/// automatically refresh when permissions change. The check methods now call
/// refresh() which publishes the updated state.
@MainActor
final class PermissionManager: ObservableObject {
    enum RefreshReason: String {
        case initialization
        case applicationLaunch
        case applicationDidBecomeActive
        case popoverWillOpen
        case settingsReturn
        case retry
        case manualRefresh
        case microphoneRequestCompletion
        case accessibilityRequest
    }

    enum PermissionStatus: Equatable, CustomStringConvertible {
        case granted
        case denied
        case notDetermined

        var description: String {
            switch self {
            case .granted: return "granted"
            case .denied: return "denied"
            case .notDetermined: return "notDetermined"
            }
        }
    }

    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityStatus: Bool = false
    @Published private(set) var lastRefreshReason: RefreshReason = .initialization
    private let provider: PermissionStatusProviding
    private let recordsDiagnostics: Bool

    var accessibilityPermissionStatus: PermissionStatus {
        accessibilityStatus ? .granted : .denied
    }

    init(provider: PermissionStatusProviding = SystemPermissionStatusProvider(),
         recordsDiagnostics: Bool = true) {
        self.provider = provider
        self.recordsDiagnostics = recordsDiagnostics
        refresh(reason: .initialization)
    }

    /// Refresh both permission statuses and publish changes to trigger UI updates.
    /// This should be called when the popover opens, when Retry is clicked,
    /// and when the user returns from System Settings.
    func refresh(reason: RefreshReason = .manualRefresh) {
        let oldMicStatus = microphoneStatus
        let oldAccStatus = accessibilityStatus
        lastRefreshReason = reason

        microphoneStatus = checkMicrophone()
        accessibilityStatus = checkAccessibility()

        // Log if status changed
        if oldMicStatus != microphoneStatus {
            logger.info("Microphone status changed: \(oldMicStatus) → \(self.microphoneStatus)")
        }
        if oldAccStatus != accessibilityStatus {
            logger.info("Accessibility status changed: \(oldAccStatus) → \(self.accessibilityStatus)")
        }
        writePermissionSnapshot(reason: reason)
    }

    func checkMicrophone() -> PermissionStatus {
        let status = provider.microphoneAuthorizationStatus()
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

    /// Request microphone permission (used on macOS 14+)
    /// Note: AVCaptureDevice.requestAccess is deprecated in macOS 14, but ASAuthorization
    /// alternative is not yet publicly available.
    func requestMicrophone() async -> PermissionStatus {
        // No replacement API exists yet - using deprecated API
        let granted = await provider.requestMicrophoneAccess()
        logger.info("Microphone request result: \(granted)")
        refresh(reason: .microphoneRequestCompletion)
        return microphoneStatus
    }

    /// Request microphone permission using legacy AVCaptureDevice API (macOS 13 and earlier)
    @available(macOS, introduced: 10.15, deprecated: 14.0, message: "Use requestMicrophone() for macOS 14+")
    func requestMicrophoneLegacy() async -> PermissionStatus {
        await requestMicrophone()
    }

    func checkAccessibility() -> Bool {
        let trusted = provider.isAccessibilityTrusted()
        logger.info("Accessibility trust state: \(trusted)")
        return trusted
    }

    /// Prompts the user to grant Accessibility permission if needed.
    func requestAccessibilityIfNeeded() -> Bool {
        if provider.isAccessibilityTrusted() {
            logger.info("Accessibility already trusted")
            refresh(reason: .accessibilityRequest)
            return true
        }
        logger.info("Requesting Accessibility permission")
        let result = provider.requestAccessibilityPrompt()
        logger.info("Accessibility request OSStatus=\(result)")
        refresh(reason: .accessibilityRequest)
        return result
    }

    // P1-1 Fix: Poll for Accessibility permission with timeout
    // Returns true if granted within timeout, false otherwise
    public func ensureAccessibilityPermission(timeoutSeconds: Int = 30) async -> Bool {
        // Immediate check
        if provider.isAccessibilityTrusted() {
            logger.info("Accessibility already trusted")
            refresh(reason: .accessibilityRequest)
            return true
        }

        // Prompt user
        _ = requestAccessibilityIfNeeded()

        // Poll for permission grant (user may take time in System Settings)
        logger.info("Polling for Accessibility permission (timeout: \(timeoutSeconds)s)...")
        for _ in 0..<timeoutSeconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
            if provider.isAccessibilityTrusted() {
                logger.info("Accessibility granted after polling")
                refresh(reason: .accessibilityRequest) // Publish the updated status
                return true
            }
        }

        logger.warning("Accessibility not granted within \(timeoutSeconds) seconds")
        refresh(reason: .accessibilityRequest)
        return false
    }

    private func writePermissionSnapshot(reason: RefreshReason) {
        guard recordsDiagnostics else { return }

        let bundle = Bundle.main
        let cdHash = currentCDHash() ?? "unavailable"
        let fields = [
            "reason=\(reason.rawValue)",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "bundle_id=\(bundle.bundleIdentifier ?? "unknown")",
            "bundle_path=\(bundle.bundlePath)",
            "executable_path=\(bundle.executablePath ?? "unknown")",
            "cdhash=\(cdHash)",
            "microphone=\(microphoneStatus.description)",
            "accessibility=\(accessibilityStatus)",
            "ui_accessibility=\(accessibilityPermissionStatus.description)",
            "application_active=\(NSApplication.shared.isActive)",
            "main_thread=\(Thread.isMainThread)"
        ]
        let line = "[\(Date().ISO8601Format())] permission_snapshot \(fields.joined(separator: " "))\n"
        if let data = line.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: permissionDiagnosticsPath) {
                fileHandle.seekToEndOfFile()
                try? fileHandle.write(contentsOf: data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: permissionDiagnosticsPath))
            }
        }
    }

    private func currentCDHash() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let unique = dictionary[kSecCodeInfoUnique as String] as? Data else {
            return nil
        }

        return unique.map { String(format: "%02x", $0) }.joined()
    }
}

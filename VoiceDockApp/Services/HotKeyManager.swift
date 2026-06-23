//
//  HotKeyManager.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import Carbon
import Foundation
import os.log

fileprivate let logger = Logger(subsystem: "com.voicedock.app", category: "HotKeyManager")

/// Thread-safe mutable holder for keyDown flag with explicit locking.
final class HotKeyState: @unchecked Sendable {
    private var _keyDown = false
    private let lock = NSLock()

    func setDown(_ value: Bool) {
        lock.lock()
        _keyDown = value
        lock.unlock()
    }

    func isDown() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _keyDown
    }
}

/// Holds the user-supplied onStart/onStop callbacks as @unchecked Sendable.
final class HotKeyCallbackStorage: @unchecked Sendable {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
}

/// Detects Control+Option+Space using Carbon RegisterEventHotKey (primary)
/// with NSEvent local+global monitors as fallback.
@MainActor
final class HotKeyManager {
    // MARK: - Carbon HotKey
    private var carbonHotKeyRef: EventHotKeyRef?
    private let carbonHotKeyID = EventHotKeyID(signature: OSType(0x56444B4D), id: 1) // 'VDKM'
    private var carbonEventHandlerRef: EventHandlerRef?

    // MARK: - NSEvent Fallback
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var localFlagsMonitor: Any?

    // MARK: - State (all @MainActor isolated)
    private let state = HotKeyState()
    private let storage = HotKeyCallbackStorage()
    private var isCarbonBackend: Bool

    var backendName: String { isCarbonBackend ? "Carbon" : "NSEvent" }
    var registrationStatus: String { isCarbonBackend ? carbonStatus : nsEventStatus }
    var lastKeyEvent: String { state.isDown() ? "pressed" : "released" }
    var pressCount: Int { _pressCount }
    var releaseCount: Int { _releaseCount }
    private var _pressCount = 0
    private var _releaseCount = 0
    private var carbonStatus = "not attempted"
    private var nsEventStatus = "not attempted"

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - C-compatible Carbon callback (must be @convention(c) - no captures)
    private static let carbonCallback: EventHandlerUPP = { (_, event, userData) -> OSStatus in
        guard let userData = userData else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleCarbonEvent(event)
    }

    init(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.storage.onStart = onStart
        self.storage.onStop = onStop
        self.isCarbonBackend = false
        _ = (onStart, onStop)

        // Try Carbon first; fall back to NSEvent
        var carbonSucceeded = false
        var status = noErr

        // Install Carbon event handler for hotkey press/release
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        status = InstallEventHandler(
            GetApplicationEventTarget(),
            HotKeyManager.carbonCallback,
            2,
            eventTypes,
            selfPtr,
            &carbonEventHandlerRef
        )

        if status == noErr, let handlerRef = carbonEventHandlerRef {
            // Register Control+Option+Space (keyCode 49 = Space, modifiers: Control + Option)
            var hotKeyRef: EventHotKeyRef?
            status = RegisterEventHotKey(
                49,                          // Space key code
                UInt32(controlKey | optionKey), // Control + Option (no Command)
                carbonHotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr {
                carbonSucceeded = true
                carbonHotKeyRef = hotKeyRef
                carbonStatus = "success"
                logger.info("Carbon hotkey registered: Control+Option+Space")
            } else {
                carbonStatus = "RegisterEventHotKey failed: \(status)"
                // P1-2 Fix: Diagnose Carbon error codes
                diagnoseCarbonFailure(status, stage: "RegisterEventHotKey")
                RemoveEventHandler(handlerRef)
                carbonEventHandlerRef = nil
            }
        } else {
            carbonStatus = "InstallEventHandler failed: \(status)"
            diagnoseCarbonFailure(status, stage: "InstallEventHandler")
        }

        self.isCarbonBackend = carbonSucceeded

        if !carbonSucceeded {
            logger.info("Falling back to NSEvent monitors")
        }
    }

    // MARK: - Carbon Event Handling
    nonisolated private func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        let eventKind = GetEventKind(event)

        if eventKind == UInt32(kEventHotKeyPressed) {
            let manager = self
            // Check state without lock (treating HotKeyState as atomic via NSLock)
            if !manager.state.isDown() {
                manager.state.setDown(true)
                // Move all MainActor-isolated access into DispatchQueue.main
                DispatchQueue.main.async { [weak manager] in
                    guard let manager = manager else { return }
                    manager._pressCount += 1
                    let count = manager._pressCount
                    manager.writeRuntimeDiagnostic("HOTKEY_PRESS: count=\(count)")
                    manager.storage.onStart?()
                }
            }
            return noErr
        } else if eventKind == UInt32(kEventHotKeyReleased) {
            let manager = self
            if manager.state.isDown() {
                manager.state.setDown(false)
                // Move all MainActor-isolated access into DispatchQueue.main
                DispatchQueue.main.async { [weak manager] in
                    guard let manager = manager else { return }
                    manager._releaseCount += 1
                    let count = manager._releaseCount
                    manager.writeRuntimeDiagnostic("HOTKEY_RELEASE: count=\(count)")
                    manager.storage.onStop?()
                }
            }
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }

    // P1-2 Fix: Diagnose Carbon error codes
    private func diagnoseCarbonFailure(_ status: OSStatus, stage: String) {
        // Carbon error codes as OSStatus (Int32)
        let paramErrValue: OSStatus = -9878
        let invalidIndexErrValue: OSStatus = -9873
        let permErrValue: OSStatus = -600

        switch status {
        case paramErrValue:
            logger.warning("Carbon \(stage) failed: paramErr (-9878)")
            logger.warning("  Possible causes:")
            logger.warning("  - Accessibility permission not granted")
            logger.warning("  - Invalid event type or modifiers")
            logger.warning("  - Hotkey conflict with system or another app")
            logger.warning("  Falling back to NSEvent monitors (app-local only)")
        case invalidIndexErrValue:
            logger.warning("Carbon \(stage) failed: invalidIndexErr (-9873)")
            logger.warning("  Event type not supported by Carbon")
        case permErrValue:
            logger.warning("Carbon \(stage) failed: permErr (-600)")
            logger.warning("  Permission denied by system")
        default:
            logger.error("Carbon \(stage) failed: unknown error \(status)")
            logger.error("  This is a non-standard Carbon error code")
        }

        // Update status for diagnostics
        if stage == "RegisterEventHotKey" {
            carbonStatus = "failed: \(status)"
        } else {
            carbonStatus = "failed: \(status) (\(stage))"
        }
    }

    private func writeRuntimeDiagnostic(_ message: String) {
        let line = "[\(Date().ISO8601Format())] \(message)\n"
        if let data = line.data(using: .utf8) {
            let path = "/tmp/voicedock-runtime-diagnostics.log"
            if let fileHandle = FileHandle(forWritingAtPath: path) {
                fileHandle.seekToEndOfFile()
                try? fileHandle.write(contentsOf: data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: - NSEvent Fallback Registration
    private func registerNSEventMonitors() -> Bool {
        guard !isCarbonBackend else { return true }

        unregisterNSEventMonitors()

        let storage = self.storage

        // GLOBAL monitors
        let globalKeyDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak storage] event in
            guard let storage = storage else { return }
            HotKeyManager.handleKey(event: event, isDown: true, storage: storage, state: self.state, pressCount: &self._pressCount, releaseCount: &self._releaseCount)
        }
        let globalKeyUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak storage] event in
            guard let storage = storage else { return }
            HotKeyManager.handleKey(event: event, isDown: false, storage: storage, state: self.state, pressCount: &self._pressCount, releaseCount: &self._releaseCount)
        }
        let globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak storage] event in
            guard let storage = storage else { return }
            HotKeyManager.handleFlags(event: event, storage: storage, state: self.state)
        }

        // LOCAL monitors (required - global monitors don't receive events delivered to the app itself)
        let localKeyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak storage] event in
            guard let storage = storage else { return event }
            HotKeyManager.handleKey(event: event, isDown: true, storage: storage, state: self.state, pressCount: &self._pressCount, releaseCount: &self._releaseCount)
            return event
        }
        let localKeyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak storage] event in
            guard let storage = storage else { return event }
            HotKeyManager.handleKey(event: event, isDown: false, storage: storage, state: self.state, pressCount: &self._pressCount, releaseCount: &self._releaseCount)
            return event
        }
        let localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak storage] event in
            guard let storage = storage else { return event }
            HotKeyManager.handleFlags(event: event, storage: storage, state: self.state)
            return event
        }

        // Verify all monitors registered
        let allMonitors = [globalKeyDown, globalKeyUp, globalFlags, localKeyDown, localKeyUp, localFlags]
        if allMonitors.contains(where: { $0 == nil }) {
            logger.error("One or more NSEvent monitors failed to register")
            unregisterNSEventMonitors()
            nsEventStatus = "monitor registration failed"
            return false
        }

        self.keyDownMonitor = globalKeyDown
        self.keyUpMonitor = globalKeyUp
        self.flagsMonitor = globalFlags
        self.localKeyDownMonitor = localKeyDown
        self.localKeyUpMonitor = localKeyUp
        self.localFlagsMonitor = localFlags

        nsEventStatus = "success"
        logger.info("NSEvent monitors registered (global + local)")
        return true
    }

    private func unregisterNSEventMonitors() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m); keyUpMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = localKeyDownMonitor { NSEvent.removeMonitor(m); localKeyDownMonitor = nil }
        if let m = localKeyUpMonitor { NSEvent.removeMonitor(m); localKeyUpMonitor = nil }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
    }

    // MARK: - NSEvent Static Handlers
    private static func handleKey(
        event: NSEvent,
        isDown: Bool,
        storage: HotKeyCallbackStorage,
        state: HotKeyState,
        pressCount: inout Int,
        releaseCount: inout Int
    ) {
        guard event.keyCode == 49 else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) && flags.contains(.option) else { return }

        let pressed = state.isDown()

        if isDown && !pressed {
            state.setDown(true)
            pressCount += 1
            let count = pressCount
            logger.info("NSEvent HotKey PRESSED (count: \(count))")
            DispatchQueue.main.async {
                storage.onStart?()
            }
        } else if !isDown && pressed {
            state.setDown(false)
            releaseCount += 1
            let count = releaseCount
            logger.info("NSEvent HotKey RELEASED (count: \(count))")
            DispatchQueue.main.async {
                storage.onStop?()
            }
        }
    }

    private static func handleFlags(
        event: NSEvent,
        storage: HotKeyCallbackStorage,
        state: HotKeyState
    ) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keep = flags.contains(.control) && flags.contains(.option)

        if !keep && state.isDown() {
            state.setDown(false)
            logger.info("NSEvent HotKey RELEASED (modifiers cleared)")
            DispatchQueue.main.async {
                storage.onStop?()
            }
        }
    }

    // MARK: - Public API
    func register() -> Bool {
        if isCarbonBackend {
            return carbonHotKeyRef != nil
        }
        return registerNSEventMonitors()
    }

    func unregister() {
        if isCarbonBackend {
            if let hotKeyRef = carbonHotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
                carbonHotKeyRef = nil
            }
            if let handlerRef = carbonEventHandlerRef {
                RemoveEventHandler(handlerRef)
                carbonEventHandlerRef = nil
            }
            carbonStatus = "unregistered"
            logger.info("Carbon hotkey unregistered")
        } else {
            unregisterNSEventMonitors()
            nsEventStatus = "unregistered"
            logger.info("NSEvent monitors unregistered")
        }
        state.setDown(false)
    }

    // MARK: - Test/Diagnostics
    func simulatePress() {
        if !state.isDown() {
            state.setDown(true)
            _pressCount += 1
            logger.info("SIMULATED HotKey PRESSED")
            DispatchQueue.main.async { [weak self] in
                self?.storage.onStart?()
            }
        }
    }

    func simulateRelease() {
        if state.isDown() {
            state.setDown(false)
            _releaseCount += 1
            logger.info("SIMULATED HotKey RELEASED")
            DispatchQueue.main.async { [weak self] in
                self?.storage.onStop?()
            }
        }
    }
}

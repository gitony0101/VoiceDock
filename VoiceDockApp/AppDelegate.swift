//
//  AppDelegate.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import SwiftUI
import VoiceDockCore
import os.log

private let logger = Logger(subsystem: "com.voicedock.app", category: "AppDelegate")
private let uiDiagnosticsPath = "/tmp/voicedock-ui-diagnostics.log"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: SessionCoordinator?
    private var hotKeyManager: HotKeyManager?
    private let permissions = PermissionManager()
    private var hasRequestedMicrophone = false
    private var menuClickCount = 0

    // Expose hotKeyManager for diagnostics
    var hotKeyManagerForDiagnostics: HotKeyManager? {
        return hotKeyManager
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")

        // Clear and initialize UI diagnostics file
        writeUIDiagnostic("=== VoiceDock UI Diagnostics Start ===")
        writeUIDiagnostic("launch_time=\(Date())")
        writeUIDiagnostic("main_thread=\(Thread.isMainThread)")

        // Check for self-test mode
        let selfTestMode = ProcessInfo.processInfo.arguments.contains("--self-test-popover")
        writeUIDiagnostic("self_test_mode=\(selfTestMode)")

        // 1) Install the menu bar item FIRST so the app is visibly alive.
        installMenuBarItem()
        logger.info("Menu bar item installed early")

        // Schedule full initialization for after run loop is settled
        writeUIDiagnostic("scheduling_full_init")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            Task { @MainActor in
                await self?.fullInitialize(selfTestMode: selfTestMode)
            }
        }
    }

    private func fullInitialize(selfTestMode: Bool) async {
        writeUIDiagnostic("fullInitialize_started")

        // 2) Coordinator + hotkey wiring
        writeUIDiagnostic("makeCoordinator_start")
        if let newCoordinator = makeCoordinator() {
            writeUIDiagnostic("makeCoordinator_success")
            self.coordinator = newCoordinator
            writeUIDiagnostic("coordinator_assigned")
            wirePopover(to: newCoordinator)
            writeUIDiagnostic("wirePopover_done")
            installHotKey(against: newCoordinator)
            writeUIDiagnostic("installHotKey_done")
            logger.info("Coordinator wired; status=\(String(describing: newCoordinator.state))")
            writeUIDiagnostic("coordinator_wiring_complete")

            // 3) Microphone permission
            checkMicrophonePermission()

            // 4) Accessibility permission
            checkAccessibilityPermission()

            // 5) Run self-test if requested
            if selfTestMode {
                writeUIDiagnostic("Scheduling self-test in 1 second...")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await runPopoverSelfTest()
            }
        } else {
            writeUIDiagnostic("ERROR: coordinator_creation_failed")
            logger.error("Failed to create coordinator")
        }
    }

    private func writeUIDiagnostic(_ message: String) {
        let line = "[\(Date().ISO8601Format())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: uiDiagnosticsPath) {
                fileHandle.seekToEndOfFile()
                try? fileHandle.write(contentsOf: data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: uiDiagnosticsPath))
            }
        }
        // Also log through standard logger
        logger.info("UI_DIAG: \(message)")
    }

    private func installMenuBarItem() {
        writeUIDiagnostic("installMenuBarItem_start")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        writeUIDiagnostic("statusItem_created=\(item != nil)")

        guard let button = item.button else {
            writeUIDiagnostic("ERROR: status_button_nil")
            logger.error("Status item button is nil")
            return
        }

        writeUIDiagnostic("button_exists=true")
        writeUIDiagnostic("button_window_exists=\(button.window != nil)")

        button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceDock")
        button.imagePosition = .imageOnly
        button.toolTip = "VoiceDock — hold Control+Option+Space"
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp])
        button.isEnabled = true

        self.statusItem = item
        writeUIDiagnostic("menu_bar_installed")
        logger.info("Menu bar item installed with action")
    }

    private func wirePopover(to coordinator: SessionCoordinator) {
        writeUIDiagnostic("wirePopover_start")

        let rootView = MenuBarView(coordinator: coordinator, permissions: permissions)
        let controller = NSHostingController(rootView: rootView)

        writeUIDiagnostic("content_view_controller_created=\(controller != nil)")

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.contentViewController = controller

        writeUIDiagnostic("popover_created=true")
        writeUIDiagnostic("popover_content_size=\(popover.contentSize.width)x\(popover.contentSize.height)")
        writeUIDiagnostic("popover_behavior=\(popover.behavior)")
        writeUIDiagnostic("popover_animates=\(popover.animates)")

        self.popover = popover
        writeUIDiagnostic("popover_assigned_to_self")
    }

    private func runPopoverSelfTest() async {
        writeUIDiagnostic("=== SELF_TEST_START ===")

        // Verify prerequisites
        let hasButton = self.statusItem?.button != nil
        let hasPopover = self.popover != nil
        let hasContentVC = self.popover?.contentViewController != nil

        writeUIDiagnostic("SELF_TEST_PREREQUISITES:")
        writeUIDiagnostic("  hasButton=\(hasButton)")
        writeUIDiagnostic("  hasPopover=\(hasPopover)")
        writeUIDiagnostic("  hasContentVC=\(hasContentVC)")

        guard hasButton && hasPopover && hasContentVC else {
            writeUIDiagnostic("SELF_TEST_OPEN: FAIL (prerequisites not met)")
            writeUIDiagnostic("=== SELF_TEST_END ===")
            return
        }

        // Test OPEN
        guard let button = self.statusItem?.button, let popover = self.popover else {
            writeUIDiagnostic("SELF_TEST_OPEN: FAIL (nil guard)")
            writeUIDiagnostic("=== SELF_TEST_END ===")
            return
        }

        writeUIDiagnostic("popover_is_shown_before_open=\(popover.isShown)")
        writeUIDiagnostic("calling_popover_show")

        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        writeUIDiagnostic("show_called=true")

        // Give it time to appear
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        guard let popover = self.popover else {
            writeUIDiagnostic("SELF_TEST_OPEN: FAIL (popover nil after delay)")
            writeUIDiagnostic("=== SELF_TEST_END ===")
            return
        }

        writeUIDiagnostic("popover_is_shown_after_open=\(popover.isShown)")
        writeUIDiagnostic("popover_window_exists=\(popover.contentViewController?.view.window != nil)")

        if popover.isShown {
            writeUIDiagnostic("SELF_TEST_OPEN: PASS")

            // Test CLOSE
            writeUIDiagnostic("calling_popover_performClose")
            popover.performClose(nil)

            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            guard let popover = self.popover else {
                writeUIDiagnostic("SELF_TEST_CLOSE: FAIL (popover nil after close)")
                writeUIDiagnostic("=== SELF_TEST_END ===")
                return
            }

            writeUIDiagnostic("popover_is_shown_after_close=\(popover.isShown)")

            if !popover.isShown {
                writeUIDiagnostic("SELF_TEST_CLOSE: PASS")
            } else {
                writeUIDiagnostic("SELF_TEST_CLOSE: FAIL (still shown)")
            }

            writeUIDiagnostic("=== SELF_TEST_END ===")

            // Keep process alive briefly for inspection
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            writeUIDiagnostic("self_test_complete_keeping_alive")
        } else {
            // Debug: try alternative presentation
            writeUIDiagnostic("popover_not_shown_attempting_alternative")
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)

            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            writeUIDiagnostic("popover_is_shown_after_makeKey=\(self.popover?.isShown ?? false)")
            writeUIDiagnostic("SELF_TEST_OPEN: FAIL")
            writeUIDiagnostic("=== SELF_TEST_END ===")
        }
    }

    private func checkMicrophonePermission() {
        let status = permissions.checkMicrophone()
        logger.info("Microphone status: \(String(describing: status))")

        switch status {
        case .notDetermined:
            guard !hasRequestedMicrophone else { return }
            hasRequestedMicrophone = true
            Task { @MainActor in
                let granted = await self.permissions.requestMicrophone()
                logger.info("Microphone prompt result: \(String(describing: granted))")
            }
        case .granted:
            logger.info("Microphone already granted")
        case .denied:
            logger.info("Microphone denied; status bar will show permission row")
        }
    }

    private func checkAccessibilityPermission() {
        let trusted = permissions.checkAccessibility()
        logger.info("Accessibility trusted: \(trusted)")
        writeUIDiagnostic("accessibility_trusted=\(trusted)")
        if trusted {
            return
        }
        // Defer the prompt slightly so the menu bar item can render the UI first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            let prompted = self.permissions.requestAccessibilityIfNeeded()
            logger.info("Accessibility prompt triggered: \(prompted == false ? "system dialog shown" : "already trusted")")
        }
    }

    private func makeCoordinator() -> SessionCoordinator? {
        writeUIDiagnostic("creating_audioCapture")
        let audioCapture = AudioCapture()
        writeUIDiagnostic("creating_asrProvider")
        let asrProvider = MLXAudioSTTProvider()
        writeUIDiagnostic("creating_transcriptDestination")
        let transcriptDestination = TranscriptDestination()
        writeUIDiagnostic("creating_coordinator")
        let coord = SessionCoordinator(
            audioCapture: audioCapture,
            asrProvider: asrProvider,
            transcriptDestination: transcriptDestination
        )
        writeUIDiagnostic("coordinator_created")
        return coord
    }

    private func installHotKey(against coordinator: SessionCoordinator) {
        let coordinatorRef = self.coordinator
        let manager = HotKeyManager(
            onStart: {
                Task { @MainActor in
                    coordinatorRef?.startRecording()
                }
            },
            onStop: {
                Task { @MainActor in
                    coordinatorRef?.stopRecording()
                }
            }
        )

        // Check accessibility trust before registering
        let trusted = AXIsProcessTrusted()
        logger.info("Accessibility trusted at hotkey registration: \(trusted)")

        if !trusted {
            logger.error("Accessibility not trusted - hotkey will not work until granted")
            writeUIDiagnostic("hotkey_accessibility_not_trusted")
            // Still create manager for diagnostics, but don't register
            hotKeyManager = manager
            return
        }

        let registered = manager.register()
        logger.info("HotKey.register result: \(registered) backend=\(manager.backendName) status=\(manager.registrationStatus)")
        writeUIDiagnostic("hotkey_registered=\(registered) backend=\(manager.backendName) status=\(manager.registrationStatus)")
        if registered {
            hotKeyManager = manager
        } else {
            logger.error("Hotkey registration failed - hotkey will not work")
            writeUIDiagnostic("hotkey_registration_failed")
            hotKeyManager = manager // Keep for diagnostics
        }
    }

    @objc nonisolated private func togglePopover(_ sender: Any?) {
        // AppKit dispatches this on the main thread via sendAction:to:from:
        // Use assumeIsolated to safely access @MainActor-isolated stored properties
        // without triggering the executor verification check that crashed in Candidate 1
        // (the DispatchMainExecutor.shared singleton's metadata was corrupted).
        MainActor.assumeIsolated {
            self.writeUIDiagnostic("togglePopover_called")
            self.writeUIDiagnostic("main_thread=\(Thread.isMainThread)")

            self.menuClickCount += 1
            self.statusItem?.button?.title = "🎙︎\(self.menuClickCount)"
            logger.info("Menu click count: \(self.menuClickCount)")
            self.writeUIDiagnostic("menu_click_count=\(self.menuClickCount)")

            guard let button = self.statusItem?.button else {
                self.writeUIDiagnostic("toggle_failed_button_nil")
                logger.error("togglePopover: button is nil")
                return
            }

            self.writeUIDiagnostic("button_exists=true")
            self.writeUIDiagnostic("button_window_exists=\(button.window != nil)")
            self.writeUIDiagnostic("button_frame=\(button.bounds)")

            guard let popover = self.popover else {
                self.writeUIDiagnostic("toggle_failed_popover_nil")
                logger.error("togglePopover: popover is nil")
                return
            }

            self.writeUIDiagnostic("popover_exists=true")

            guard popover.contentViewController != nil else {
                self.writeUIDiagnostic("toggle_failed_content_controller_nil")
                logger.error("togglePopover: contentViewController is nil")
                return
            }

            self.writeUIDiagnostic("content_view_controller_exists=true")
            self.writeUIDiagnostic("popover_is_shown_before=\(popover.isShown)")
            self.writeUIDiagnostic("popover_content_size=\(popover.contentSize)")

            if popover.isShown {
                popover.performClose(nil)
                self.writeUIDiagnostic("popover_performClose_called")
                self.writeUIDiagnostic("popover_closed=true")
                logger.info("Popover closed")
                return
            }

            NSApplication.shared.activate(ignoringOtherApps: true)
            self.writeUIDiagnostic("activate_ignoring_other_apps_called")

            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.writeUIDiagnostic("popover_show_called")
            self.writeUIDiagnostic("popover_is_shown_after=\(popover.isShown)")

            if let popoverWindow = popover.contentViewController?.view.window {
                self.writeUIDiagnostic("popover_window_frame=\(popoverWindow.frame)")
                self.writeUIDiagnostic("popover_window_isVisible=\(popoverWindow.isVisible)")
                self.writeUIDiagnostic("popover_window_isKeyWindow=\(popoverWindow.isKeyWindow)")
            }

            logger.info("Popover opened")
        }
    }

    // MARK: - Diagnostic Test Endpoint
    @objc nonisolated private func handleDiagnosticTest(_ notification: Notification) {
        let action = (notification.userInfo?["action"] as? String) ?? ""
        MainActor.assumeIsolated {
            self.writeUIDiagnostic("DIAGNOSTIC_TEST: \(action)")

            switch action {
            case "press":
                self.hotKeyManager?.simulatePress()
                self.writeUIDiagnostic("SIMULATE_PRESS_INVOKED")
            case "release":
                self.hotKeyManager?.simulateRelease()
                self.writeUIDiagnostic("SIMULATE_RELEASE_INVOKED")
            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("applicationWillTerminate")
        writeUIDiagnostic("=== VoiceDock UI Diagnostics End ===")
        coordinator?.cleanup()
        hotKeyManager?.unregister()
    }
}
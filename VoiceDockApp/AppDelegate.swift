//
//  AppDelegate.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: SessionCoordinator?
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create coordinator first
        coordinator = SessionCoordinator()

        // Set up hotkey manager with callbacks to coordinator
        hotKeyManager = HotKeyManager(
            onStart: { [weak self] in
                Task { @MainActor in
                    self?.coordinator?.startRecording()
                }
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    self?.coordinator?.stopRecording()
                }
            }
        )
        _ = hotKeyManager?.register()

        // Set up menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "VoiceDock"
        statusItem?.button?.action = #selector(togglePopover)

        // Set up popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 200)
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView(coordinator: coordinator!)
        )
    }

    @MainActor @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.cleanup()
    }
}
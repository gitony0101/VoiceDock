//
//  VoiceDockApp.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import SwiftUI
import VoiceDockCore

@main
struct VoiceDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
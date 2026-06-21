//
//  VoiceDockApp.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import SwiftUI

@main
struct VoiceDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = SessionCoordinator()

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
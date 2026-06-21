//
//  StatusPopover.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import SwiftUI

struct StatusPopover: View {
    @ObservedObject var coordinator: SessionCoordinator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 12) {
            // Current state
            Text(stateDescription)
                .font(.headline)

            // Progress indicator if loading/transcribing
            if coordinator.state == .loading || coordinator.state == .transcribing {
                ProgressView()
            }

            // Permission buttons
            if case .permissionRequired(let type) = coordinator.state {
                Button(action: { coordinator.requestPermission(type: type) }) {
                    Text("Open Settings")
                }
            }

            // Quit action
            Button("Quit") {
                Task { await coordinator.quit() }
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 250, height: 120)
    }

    private var stateDescription: String {
        switch coordinator.state {
        case .idle: return "Ready"
        case .loading: return "Loading..."
        case .ready: return "Ready"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .delivering: return "Delivering..."
        case .error(let msg): return msg
        case .permissionRequired(let type): return "Permission Required: \(type)"
        }
    }
}

#Preview {
    StatusPopover(coordinator: SessionCoordinator())
}
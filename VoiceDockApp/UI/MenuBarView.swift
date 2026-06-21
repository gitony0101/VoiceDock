//
//  MenuBarView.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: SessionCoordinator

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(stateColor)
                Text(stateText)
                    .font(.headline)
            }

            if let transcript = coordinator.currentTranscript {
                Text(transcript)
                    .font(.body)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }

            Button(action: {}) {
                Text("Push to Talk")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!isReady)
        }
        .padding()
        .frame(width: 280, height: 180)
    }

    private var stateText: String {
        switch coordinator.state {
        case .idle: return "Ready"
        case .loading: return "Loading..."
        case .ready: return "Ready"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .delivering: return "Delivering..."
        case .error(let message): return message
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle, .ready: return .green
        case .loading: return .orange
        case .listening: return .blue
        case .transcribing: return .purple
        case .delivering: return .green
        case .error: return .red
        }
    }

    private var isReady: Bool {
        coordinator.state == .ready
    }
}

#Preview {
    MenuBarView(coordinator: SessionCoordinator())
}
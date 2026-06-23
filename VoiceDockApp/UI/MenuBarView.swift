//
//  MenuBarView.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import SwiftUI
import VoiceDockCore

struct MenuBarView: View {
    @ObservedObject var coordinator: SessionCoordinator
    let permissions: PermissionManager
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(stateColor)
                Text("VoiceDock")
                    .font(.headline)
                Spacer()
                if let transcript = coordinator.currentTranscript {
                    Text("\(transcript.count) chars")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Current state
            HStack {
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else if hasFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
                Text(stateText)
                    .font(.body)
            }

            // Permission row
            VStack(alignment: .leading, spacing: 4) {
                permissionRow(
                    name: "Microphone",
                    status: permissions.checkMicrophone()
                )
                permissionRow(
                    name: "Accessibility",
                    status: permissions.checkAccessibility() ? .granted : .denied
                )
            }

            // Hotkey Diagnostics
            if showDiagnostics, let appDelegate = NSApp.delegate as? AppDelegate,
               let hk = appDelegate.hotKeyManagerForDiagnostics {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hotkey Diagnostics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("Accessibility trusted:")
                        Text(hk.accessibilityTrusted ? "true" : "false")
                            .foregroundColor(hk.accessibilityTrusted ? .green : .red)
                    }
                    .font(.caption)
                    HStack {
                        Text("Backend:")
                        Text(hk.backendName)
                    }
                    .font(.caption)
                    HStack {
                        Text("Registration:")
                        Text(hk.registrationStatus)
                            .foregroundColor(hk.registrationStatus == "success" ? .green : .red)
                    }
                    .font(.caption)
                    HStack {
                        Text("Last event:")
                        Text(hk.lastKeyEvent)
                    }
                    .font(.caption)
                    HStack {
                        Text("Press count: \(hk.pressCount)")
                        Spacer()
                        Text("Release count: \(hk.releaseCount)")
                    }
                    .font(.caption)

                    // Test button
                    Button("Test Coordinator Callbacks") {
                        Task { @MainActor in
                            hk.simulatePress()
                            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                            hk.simulateRelease()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            if case .failed(let msg) = coordinator.state {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }

            // Last transcript
            if let transcript = coordinator.currentTranscript {
                Divider()
                Text("Last transcript:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(transcript)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
            }

            Spacer()

            Divider()

            // Action buttons
            HStack {
                Button("Open Mic Settings") {
                    openMicrophoneSettings()
                }
                .font(.caption)
                Spacer()
                Button("Open Acc. Settings") {
                    openAccessibilitySettings()
                }
                .font(.caption)
                Spacer()
                Button(showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics") {
                    showDiagnostics.toggle()
                }
                .font(.caption)
                Spacer()
                Button("Retry") {
                    Task { @MainActor in
                        await coordinator.retry()
                    }
                }
                .font(.caption)
                .disabled(!isReadyOrFailed)
                Spacer()
                Button("Quit") {
                    coordinator.quit()
                }
                .font(.caption)
            }
        }
        .padding()
        .frame(width: 340, height: 420)
    }

    private var stateText: String {
        switch coordinator.state {
        case .idle, .ready: return "Ready — hold Control+Option+Space"
        case .starting: return "Starting…"
        case .waitingForMicrophonePermission: return "Waiting for Microphone permission…"
        case .waitingForAccessibilityPermission: return "Waiting for Accessibility permission…"
        case .loadingModel: return "Loading model (first launch ~1 min)…"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing audio…"
        case .delivering: return "Delivering transcript…"
        case .failed(let msg): return msg
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle, .ready: return .green
        case .starting, .loadingModel: return .orange
        case .waitingForMicrophonePermission, .waitingForAccessibilityPermission: return .yellow
        case .listening: return .blue
        case .transcribing: return .purple
        case .delivering: return .green
        case .failed: return .red
        }
    }

    private var showsSpinner: Bool {
        switch coordinator.state {
        case .starting, .loadingModel, .listening, .transcribing, .delivering, .waitingForMicrophonePermission, .waitingForAccessibilityPermission: return true
        default: return false
        }
    }

    private var hasFailed: Bool {
        if case .failed = coordinator.state { return true }
        return false
    }

    private var isReadyOrFailed: Bool {
        switch coordinator.state {
        case .ready, .failed, .idle: return true
        default: return false
        }
    }

    private func permissionRow(name: String, status: PermissionManager.PermissionStatus) -> some View {
        HStack {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : (status == .denied ? "xmark.circle.fill" : "questionmark.circle.fill"))
                .foregroundColor(status == .granted ? .green : (status == .denied ? .red : .orange))
            Text(name)
                .font(.caption)
            Spacer()
            Text(statusText(status))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func statusText(_ s: PermissionManager.PermissionStatus) -> String {
        switch s {
        case .granted: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "ask"
        }
    }

    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    let coord = SessionCoordinator(audioCapture: nil, asrProvider: nil, transcriptDestination: nil)
    return MenuBarView(coordinator: coord, permissions: PermissionManager())
}
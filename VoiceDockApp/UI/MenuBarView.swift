//
//  MenuBarView.swift
//  VoiceDock (0.2 — Stable Identity + Accessibility)
//

import SwiftUI
import VoiceDockCore
import os.log

private let logger = Logger(subsystem: "com.voicedock.app", category: "MenuBarView")

struct MenuBarView: View {
    @ObservedObject var coordinator: SessionCoordinator
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var modelStatus: ModelStatus
    @State private var showFullTranscript = false
    @State private var showDiagnostics = false
    @State private var automaticPaste: Bool
    @State private var sendReturnAfterPaste: Bool
    @State private var correctionEnabled: Bool
    @State private var restartInProgress = false
    @State private var restartProgressText: String = ""

    init(coordinator: SessionCoordinator, permissions: PermissionManager, modelStatus: ModelStatus) {
        self.coordinator = coordinator
        self.permissions = permissions
        self.modelStatus = modelStatus
        let deliveryPrefs = TranscriptDeliveryPreferences.load()
        _automaticPaste = State(initialValue: deliveryPrefs.automaticPaste)
        _sendReturnAfterPaste = State(initialValue: deliveryPrefs.sendReturnAfterPaste)
        let correctionPrefs = TranscriptCorrectionPreferences.load()
        _correctionEnabled = State(initialValue: correctionPrefs.mode == .personalCorrection)
    }

    var body: some View {
        // Adapt to screen: bounded width, height based on visible screen space
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let maxHeight = max(480, min(720, screenFrame.height - 60))

        VStack(alignment: .leading, spacing: 0) {
            // Fixed header
            headerSection

            Divider()

            // Bounded / collapsible transcript
            transcriptSection

            // Fixed output controls
            deliverySection

            Divider()

            // Fixed model controls (always visible, never clipped)
            modelSection

            Divider()

            // Fixed correction control
            correctionSection

            Divider()

            // Fixed permission row (compact unless denied, then expandable)
            permissionSection

            Spacer(minLength: 8)

            // Fixed footer: always shows Quit VoiceDock
            footerSection
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 400)
        .frame(maxHeight: maxHeight)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            permissions.refresh(reason: .popoverWillOpen)
        }
        // Cross-report coordinator load failures into ModelStatus so a Fast
        // load failure surfaces as a visible error AND keeps the Fast
        // selection — no silent Quality fallback in the UI.
        .onChange(of: coordinator.state) { newState in
            if case .failed(let message) = newState {
                if message.lowercased().contains("load") || message.lowercased().contains("model") {
                    modelStatus.recordLoadError(message)
                }
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(stateColor)
                Text("VoiceDock")
                    .font(.title3.bold())
                Spacer()
                statusBadge
            }
            Text("Hold Control–Option–Space")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        Group {
            switch coordinator.state {
            case .ready, .idle:
                if !permissions.microphoneStatus.isGranted {
                    Text("Microphone Required")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
                } else if !permissions.accessibilityStatus {
                    Text("Accessibility Required")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
                } else {
                    Text("Ready")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
                }
            case .listening:
                Text("Recording")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
            case .transcribing:
                Text("Transcribing")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
            case .delivering:
                Text("Delivering")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
            case .loadingModel:
                Text("Loading Model")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
            case .failed(let msg):
                Text("Error")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red.opacity(0.2)).cornerRadius(4).foregroundColor(.primary)
            default:
                Text(stateText)
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15)).cornerRadius(4).foregroundColor(.secondary)
            }
        }
    }

    private var stateText: String {
        switch coordinator.state {
        case .idle, .ready:
            if !permissions.microphoneStatus.isGranted { return "Microphone Required" }
            if !permissions.accessibilityStatus { return "Accessibility Required" }
            return "Ready"
        case .starting: return "Starting"
        case .waitingForMicrophonePermission: return "Waiting — Microphone"
        case .waitingForAccessibilityPermission: return "Waiting — Accessibility"
        case .loadingModel: return "Loading Model"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .delivering: return "Delivering"
        case .failed(let msg): return msg
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle, .ready: return .green
        case .starting, .loadingModel: return .orange
        case .listening: return .blue
        case .transcribing: return .purple
        case .delivering: return .green
        case .waitingForMicrophonePermission, .waitingForAccessibilityPermission: return .yellow
        case .failed: return .red
        }
    }

    // MARK: - Transcript (bounded, collapsible)
    private var transcriptSection: some View {
        Group {
            if let transcript = coordinator.currentTranscript, !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last Transcript")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: copyTranscript) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    // Bounded to 2 visual lines by default; expand for full
                    Text(showFullTranscript ? transcript : String(transcript.prefix(240)))
                        .font(.body)
                        .lineLimit(showFullTranscript ? nil : 2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.windowBackgroundColor).opacity(0.6))
                        .cornerRadius(6)

                    if transcript.count > 240 || transcript.contains("\n") {
                        Button(action: { showFullTranscript.toggle() }) {
                            Label(showFullTranscript ? "Show Less" : "Show Full", systemImage: "chevron.down")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }

                    if let raw = coordinator.getLastRawTranscript(),
                       !raw.isEmpty, raw != transcript {
                        HStack {
                            Spacer()
                            Button(action: copyRawTranscript) {
                                Label("Copy Raw", systemImage: "doc.plaintext")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("No transcript yet — press Control–Option–Space")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Output / Delivery (fixed, never scrollable separately)
    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Toggle("Automatically paste transcript", isOn: $automaticPaste)
                .font(.body)
                .toggleStyle(.switch)
                .onChange(of: automaticPaste) { nv in
                    let p = TranscriptDeliveryPreferences(automaticPaste: nv, sendReturnAfterPaste: sendReturnAfterPaste)
                    p.save()
                }

            Toggle("Press Return after paste", isOn: $sendReturnAfterPaste)
                .font(.body)
                .toggleStyle(.switch)
                .disabled(!automaticPaste)
                .onChange(of: sendReturnAfterPaste) { nv in
                    let p = TranscriptDeliveryPreferences(automaticPaste: automaticPaste, sendReturnAfterPaste: nv)
                    p.save()
                }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Model (always visible, action row reserved)
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack {
                Text("Active:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(activeModelDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
            }

            // Segmented picker
            Picker("Model selection", selection: Binding(
                get: { modelStatus.selectedModel },
                set: { nv in if nv != modelStatus.selectedModel { modelStatus.updateSelection(nv) } }
            )) {
                Text("Fast 0.6B").tag(ASRModelSelection.qwen3_0_6B_8bit)
                Text("Quality 1.7B").tag(ASRModelSelection.qwen3_1_7B_4bit)
            }
            .pickerStyle(.segmented)
            .disabled(restartInProgress || isRecordOrTranscribeActive)

            // Visible provider-load / restart error for the selected model.
            // This surfaces a Fast load failure rather than silently falling
            // back to Quality.
            if let loadError = modelStatus.lastLoadError {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(loadError)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(3)
                }
                .padding(.top, 2)
            }

            // Availability / error indicator
            let selected = modelStatus.selectedModel
            if let avail = modelStatus.availability[selected] {
               if avail == .missing {
                   HStack(spacing: 4) {
                       Image(systemName: "xmark.circle.fill")
                           .font(.caption)
                           .foregroundColor(.red)
                       Text("\(selectedModelDisplayName) is not installed")
                           .font(.caption)
                           .foregroundColor(.red)
                   }
               } else if case .invalid = avail {
                   HStack(spacing: 4) {
                       Image(systemName: "xmark.circle.fill")
                           .font(.caption)
                           .foregroundColor(.red)
                       Text("\(selectedModelDisplayName) is not installed")
                           .font(.caption)
                           .foregroundColor(.red)
                   }
               }
            }

            // Action row: always reserved. Either disabled "Current Model Active" or prominent "Apply & Restart"
            Group {
                if restartInProgress {
                    ProgressView(value: 0.5)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                    Text(restartProgressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if modelStatus.selectedModel == modelStatus.activeModel {
                    Button(action: {}) {
                        Label("Current Model Active", systemImage: "checkmark.circle.fill")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    .disabled(true)
                } else {
                    Button(action: performRestart) {
                        Label("Apply & Restart", systemImage: "arrow.clockwise")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isRecordOrTranscribeActive || modelMissingForSelection)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private var isRecordOrTranscribeActive: Bool {
        switch coordinator.state {
        case .listening, .transcribing, .loadingModel: return true
        default: return false
        }
    }

    private var modelMissingForSelection: Bool {
        let selected = modelStatus.selectedModel
        if let avail = modelStatus.availability[selected] {
            if avail == .missing {
                return true
            }
            if case .invalid = avail {
                return true
            }
            return false
        }
        return true
    }

    private var activeModelDisplayName: String {
        modelStatus.activeModel.displayName
    }

    private var selectedModelDisplayName: String {
        modelStatus.selectedModel.displayName
    }

    // MARK: - Intelligent Correction
    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Intelligent Correction")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Toggle("Correct common ASR terms", isOn: $correctionEnabled)
                .font(.body)
                .toggleStyle(.switch)
                .onChange(of: correctionEnabled) { nv in
                    let mode: TranscriptCorrectionMode = nv ? .personalCorrection : .off
                    TranscriptCorrectionPreferences(mode: mode, loadUserCorrections: true).save()
                }

            Text("Fixes known names and terms without rewriting or translating sentences.")
                .font(.caption)
                .foregroundColor(.secondary)

            let applied = coordinator.getLastAppliedCorrections()
            if !applied.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Corrected \(applied.count) term\(applied.count == 1 ? "" : "s")")
                        .font(.caption).foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Permissions (compact; expandable details hidden unless needed)
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: permissions.accessibilityStatus ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(permissions.accessibilityStatus ? .green : .red)
                Text("Accessibility")
                    .font(.caption)
                Spacer()
                Text(permissions.accessibilityStatus ? "Granted" : "Denied")
                    .font(.caption2)
                    .foregroundColor(permissions.accessibilityStatus ? .green : .red)
            }

            if !permissions.accessibilityStatus {
                Text("Accessibility required for automatic paste")
                    .font(.caption)
                    .foregroundColor(.orange)

                HStack(spacing: 6) {
                    Button("Grant Access") {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.requestAccessibilityFromUserAction()
                        } else {
                            _ = permissions.requestAccessibilityIfNeeded()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)

                    Button("Open Settings") {
                        openAccessibilitySettings()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)

                    Button("Refresh") {
                        permissions.refresh(reason: .manualRefresh)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer
    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit VoiceDock", systemImage: "power")
                        .font(.caption)
                }
                .keyboardShortcut("q", modifiers: .command)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.windowBackgroundColor).opacity(0.95))
        }
    }

    // MARK: - Actions
    private func copyTranscript() {
        guard let t = coordinator.currentTranscript, !t.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
    }

    private func copyRawTranscript() {
        guard let raw = coordinator.getLastRawTranscript(), !raw.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak permissions] in
            permissions?.refresh(reason: .settingsReturn)
        }
    }

    // MARK: - Restart (safe Apply & Restart)
    private func performRestart() {
        guard !restartInProgress else { return }
        guard modelStatus.restartRequired else { return }

        let selected = modelStatus.selectedModel
        let descriptor = selected.modelDescriptor
        let bundlePath = Bundle.main.bundlePath
        let oldPID = Int32(ProcessInfo.processInfo.processIdentifier)
        // Use the SAME preference store that ModelStatus and the factory use,
        // so persistence verification matches what the new process will read.
        let store = modelStatus.preferenceStore

        Task {
            await MainActor.run {
                restartProgressText = "Verifying model…"
                restartInProgress = true
            }

            let storage = ModelStorage()
            let isValid = await storage.isModelValid(descriptor)
            await MainActor.run {
                if !isValid {
                    restartProgressText = ""
                    restartInProgress = false
                    modelStatus.recordLoadError("\(selected.displayName) is not installed locally (path: \(modelPathDescription(for: selected))). Keeping selection; not restarting.")
                    logger.error("Restart blocked: selected model not installed")
                    return
                }
            }

            // 2. Write selection through the shared store and force a
            // cfprefs synchronization so the value is durable for the new
            // process launched by `open -n`. saveAndSynchronize returns the
            // raw value read back from the same store.
            var prefs = ASRModelPreferences.load(from: store)
            prefs.selectedModel = selected
            let readBack = prefs.saveAndSynchronize(to: store)
            let step2Verified = (readBack == selected.rawValue)
            await MainActor.run {
                guard step2Verified else {
                    restartProgressText = ""
                    restartInProgress = false
                    let msg = "Model preference verification failed: wrote \(selected.rawValue) but read back \(readBack). Not restarting to avoid loading the wrong model."
                    modelStatus.recordLoadError(msg)
                    logger.error("\(msg, privacy: .public)")
                    return
                }
                restartProgressText = "Persisting model selection…"
            }

            // 3. Re-read through the same store (no cached in-process view)
            // and require exact equality. A second process reading this
            // store immediately after must see the same value.
            let reread = store.rawSelectedModelValue()
            let step3Verified = (reread == selected.rawValue)
            await MainActor.run {
                guard step3Verified else {
                    restartProgressText = ""
                    restartInProgress = false
                    let msg = "Cross-process persistence check failed: stored value is \(reread ?? "nil"), expected \(selected.rawValue). Not restarting."
                    modelStatus.recordLoadError(msg)
                    logger.error("\(msg, privacy: .public)")
                    return
                }
                restartProgressText = "Launching helper…"
            }

            // 4. Verify embedded helper exists and is executable
            let helperPath = Bundle.main.bundlePath + "/Contents/MacOS/voice-dock-restart-helper"
            let helperExists = FileManager.default.fileExists(atPath: helperPath)
            var helperExecutable = false
            if helperExists {
                helperExecutable = FileManager.default.isExecutableFile(atPath: helperPath)
            }

            await MainActor.run {
                guard helperExists, helperExecutable else {
                    restartProgressText = ""
                    restartInProgress = false
                    let msg = "Restart helper missing or not executable at \(helperPath). Not restarting."
                    modelStatus.recordLoadError(msg)
                    logger.error("\(msg, privacy: .public)")
                    return
                }
                restartProgressText = "Waiting for new process…"
            }

            // 5. Launch the helper
            let task = Process()
            task.executableURL = URL(fileURLWithPath: helperPath)
            task.arguments = [bundlePath, String(oldPID)]
            task.standardOutput = nil
            task.standardError = nil
            do {
                try task.run()
            } catch {
                await MainActor.run {
                    restartProgressText = ""
                    restartInProgress = false
                    let msg = "Failed to launch restart helper: \(error.localizedDescription). Not restarting."
                    modelStatus.recordLoadError(msg)
                    logger.error("\(msg, privacy: .public)")
                }
                return
            }

            // Confirm helper process started by checking it exists briefly
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Only terminate if every verification passed AND the helper launched.
            await MainActor.run {
                restartProgressText = "Restarting VoiceDock…"
            }

            try? await Task.sleep(nanoseconds: 300_000_000)

            // Final re-verification immediately before terminating. If the
            // stored value changed (unlikely but possible), abort the restart
            // rather than relaunch into the wrong model.
            let finalRead = store.rawSelectedModelValue()
            let finalOK = (finalRead == selected.rawValue)
            await MainActor.run {
                guard finalOK else {
                    restartProgressText = ""
                    restartInProgress = false
                    let msg = "Pre-terminate verification failed: stored value changed to \(finalRead ?? "nil"). Not restarting."
                    modelStatus.recordLoadError(msg)
                    logger.error("\(msg, privacy: .public)")
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func modelPathDescription(for selection: ASRModelSelection) -> String {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "unknown"
        }
        return supportDir
            .appendingPathComponent("VoiceDock/Models/\(selection.modelDescriptor.canonicalDirectoryName)").path
    }
}

#Preview {
    let perm = PermissionManager()
    let coord = SessionCoordinator(audioCapture: nil, asrProvider: nil, transcriptDestination: nil)
    let modelStatus = ModelStatus(activeModel: .qwen3_1_7B_4bit, selectedModel: .qwen3_0_6B_8bit)
    return MenuBarView(coordinator: coord, permissions: perm, modelStatus: modelStatus)
}

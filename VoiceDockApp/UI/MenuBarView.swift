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
    @ObservedObject var acquisition: ModelAcquisitionController
    @State private var showFullTranscript = false
    @State private var showDiagnostics = false
    @State private var automaticPaste: Bool
    @State private var sendReturnAfterPaste: Bool
    @State private var correctionEnabled: Bool
    @State private var restartInProgress = false
    @State private var restartProgressText: String = ""

    init(coordinator: SessionCoordinator, permissions: PermissionManager, modelStatus: ModelStatus, acquisition: ModelAcquisitionController) {
        self.coordinator = coordinator
        self.permissions = permissions
        self.modelStatus = modelStatus
        self.acquisition = acquisition
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

            // Fixed model download / install state
            acquisitionSection

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
            Task { await acquisition.refreshInstalled() }
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
            case .cleaningUp:
                Text("Cleaning Up")
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15)).cornerRadius(4).foregroundColor(.secondary)
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
        case .cleaningUp: return "Cleaning Up"
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
        case .cleaningUp: return .secondary
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
                    .foregroundColor(modelStatus.activeModel == nil ? .orange : .primary)
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

            // Action row: always reserved.
            //   - restartInProgress          → progress + status text
            //   - activeModel == nil           → disabled "Starting…" (provider not
            //                                   created yet; the saved selection is
            //                                   NOT Active, and restartRequired is
            //                                   false so Apply & Restart is hidden)
            //   - selected == active           → disabled "Current Model Active"
            //   - otherwise                    → prominent "Apply & Restart"
            Group {
                if restartInProgress {
                    ProgressView(value: 0.5)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                    Text(restartProgressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if modelStatus.activeModel == nil {
                    Button(action: {}) {
                        Label("Starting…", systemImage: "circle.dotted")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    .disabled(true)
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
        // activeModel is nil until the provider is actually created (captureActive).
        // Do not force-unwrap and do not infer a display name from selectedModel
        // — the saved preference must never be presented as Active before the
        // provider exists.
        modelStatus.activeModel?.displayName ?? "Starting…"
    }

    private var selectedModelDisplayName: String {
        modelStatus.selectedModel.displayName
    }

    // MARK: - Model Downloads (acquisition, driven by ModelAcquisitionController)
    //
    // Install/download state lives in `acquisition` (authoritative storage
    // validation) and is deliberately separate from selection/active state in
    // `modelStatus`. Downloading a model never changes the selection.
    private var acquisitionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model Downloads")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            ForEach(ModelAcquisitionController.presentationOrder, id: \.self) { model in
                acquisitionRow(for: model)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func acquisitionRow(for model: ASRModelSelection) -> some View {
        let state = acquisition.state(for: model)
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body)
                    if ModelAcquisitionController.isRecommended[model] == true {
                        Text("Recommended")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Text("Optional")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                acquisitionStatus(state)
            }
            Spacer()
            acquisitionAction(state, model: model)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func acquisitionStatus(_ state: ModelAcquisitionState) -> some View {
        switch state {
        case .checking:
            Text("Checking…")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.green)
        case .idle:
            Text("Not installed")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .downloading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 180)
        case .failed(let message):
            Text(message ?? "Download failed. Try again.")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private func acquisitionAction(_ state: ModelAcquisitionState, model: ASRModelSelection) -> some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .installed:
            EmptyView()
        case .idle:
            Button("Download") {
                acquisition.download(model)
            }
            .buttonStyle(.bordered)
            .disabled(acquisitionDisabled)
        case .downloading:
            Button("Cancel") {
                acquisition.cancel()
            }
            .buttonStyle(.bordered)
            .disabled(isRecordOrTranscribeActive || restartInProgress)
        case .failed:
            Button("Retry") {
                acquisition.retry(model)
            }
            .buttonStyle(.borderedProminent)
            .disabled(acquisitionDisabled)
        }
    }

    /// Download/retry is disabled while any other acquisition op is active,
    /// or while the speech pipeline / restart is busy (single owned task).
    private var acquisitionDisabled: Bool {
        (acquisition.activeOperation != nil) || isRecordOrTranscribeActive || restartInProgress
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
    //
    // Strict order (per spec), delegated to `RestartPreflight.run(...)` so the
    // persistence and helper verifications run OUTSIDE any MainActor closure:
    //   1. validate selected model
    //   2. write preference through the shared store
    //   3. CFPreferences synchronize the suite domain, read back, verify equality
    //   4. final read through the store, verify exact equality
    //   5. verify the embedded helper exists and is executable
    //   6. only then launch the helper
    //   7. immediately request normal termination
    //
    // The helper is NOT launched before step 5. Each failure `return`s from
    // the outer `Task` (not from inside an `await MainActor.run { ... }`
    // closure — a `return` there returns only from the closure and the Task
    // would continue). The pattern is:
    //
    //   guard outcome.isOk else { await MainActor.run { updateUI }; return }
    //
    // so the Task itself stops on the failure boundary. A helper is launched
    // and the app is terminated only when the preflight returns `.ok`.
    private func performRestart() {
        guard !restartInProgress else { return }
        guard modelStatus.restartRequired else { return }

        let selected = modelStatus.selectedModel
        let bundlePath = Bundle.main.bundlePath
        let oldPID = Int32(ProcessInfo.processInfo.processIdentifier)
        // Use the SAME preference store that ModelStatus and the factory use,
        // so persistence verification matches what the new process will read.
        let store = modelStatus.preferenceStore
        let helperPath = Bundle.main.bundlePath + "/Contents/MacOS/voice-dock-restart-helper"

        Task {
            await MainActor.run {
                restartProgressText = "Verifying model…"
                restartInProgress = true
            }

            // Run the verifiable preflight (steps 1-5) OUTSIDE any MainActor
            // closure. Injected primitives match production behavior.
            let outcome = await RestartPreflight.run(
                selected: selected,
                store: store,
                helperPath: helperPath,
                modelIsValid: { desc in
                    // The selected model's descriptor is the one that must be
                    // valid locally; ignore the argument's provenance and use
                    // the canonical storage for the preflight descriptor.
                    await ModelStorage().isModelValid(desc)
                },
                helperExistsAndExecutable: {
                    let exists = FileManager.default.fileExists(atPath: helperPath)
                    return exists && FileManager.default.isExecutableFile(atPath: helperPath)
                }
            )

            // On failure: surface the UI state and STOP the Task. The `return`
            // here is on the Task, not inside an await MainActor.run closure.
            guard outcome.isOk else {
                await MainActor.run {
                    restartProgressText = ""
                    restartInProgress = false
                    if case .failure(let message) = outcome {
                        modelStatus.recordLoadError(message)
                    }
                }
                return
            }

            // 6. Only now launch the helper. A failed launch is its own
            // failure boundary: record the error and STOP the Task — no
            // termination.
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

            // 7. Immediately request normal termination. The helper waits for
            //    the old PID to exit and then `open -n`s the new instance; we
            //    terminate now so the new process inherits the verified
            //    stored preference. No further verification is performed
            //    after the launch — the last verified state is the one the
            //    new process will read.
            await MainActor.run {
                restartProgressText = "Restarting VoiceDock…"
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

#Preview {
    let perm = PermissionManager()
    let coord = SessionCoordinator(audioCapture: nil, asrProvider: nil, transcriptDestination: nil)
    let modelStatus = ModelStatus(
        activeModel: .qwen3_1_7B_4bit,
        selectedModel: .qwen3_0_6B_8bit,
        recorder: ModelLaunchRecorder.shared
    )
    let storage = ModelStorage()
    let acquisition = ModelAcquisitionController(
        installer: ModelInstaller(storage: storage),
        storage: storage,
        modelStatus: modelStatus
    )
    return MenuBarView(coordinator: coord, permissions: perm, modelStatus: modelStatus, acquisition: acquisition)
}

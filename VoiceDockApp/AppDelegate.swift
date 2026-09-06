//
//  AppDelegate.swift
//  VoiceDock
//
//  VoiceDock Push-to-Talk MVP
//

import AppKit
import SwiftUI
import VoiceDockCore
import Combine
import os.log

private let logger = Logger(subsystem: "com.voicedock.app", category: "AppDelegate")
private let uiDiagnosticsPath = "/tmp/voicedock-ui-diagnostics.log"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKeyManager: HotKeyManager?
    private let permissions = PermissionManager()
    private let preferenceStore: ASRPreferenceStore
    private let launchRecorder: ModelLaunchRecorder
    private let modelStatus: ModelStatus
    private let acquisition: ModelAcquisitionController
    /// Shared authoritative model storage, constructed once and reused by both
    /// the acquisition controller (install/validation) and the composition root
    /// (setup-required gating), so both share one view of the on-disk models.
    private let storage: ModelStorage
    private var coordinator: SessionCoordinator?
    private var hasRequestedMicrophone = false
    private var hasPressed = false  // Track whether press was accepted
    private var menuClickCount = 0
    private var menuClickTimestamp: Date?
    private var activationObserver: NSObjectProtocol?
    private(set) var activationObserverInstallCount = 0
    /// Combine subscription on `coordinator.state` used to drive the
    /// exactly-once terminal diagnostic finalizer. Held for lifetime.
    private var lifecycleFinalizerCancellable: AnyCancellable?
    /// Single stable CoordinatorBox for the popover's lifetime.
    private var coordinatorBox: CoordinatorBox?

    /// Default initializer invoked by `@NSApplicationDelegateAdaptor(AppDelegate.self)`
    /// at host app launch. Obtains the preference store and per-launch recorder
    /// from the runtime composition, so the Xcode TEST_HOST (launched with
    /// `VOICEDOCK_TEST_MODE=1` by the test action before `AppDelegate.init()`
    /// runs) binds an isolated PID+UUID preference suite and a temp-directory
    /// recorder — never the production `com.voicedock.app.asr-prefs` suite and
    /// never `ModelLaunchRecorder.shared`. A normal owner launch resolves to
    /// the production composition (`ASRPreferenceStore.production` +
    /// `ModelLaunchRecorder.shared`).
    override init() {
        let composition = VoiceDockRuntimeComposition.current
        self.preferenceStore = composition.preferenceStore
        self.launchRecorder = composition.launchRecorder
        self.modelStatus = ModelStatus(
            preferenceStore: self.preferenceStore,
            recorder: self.launchRecorder
        )
        self.storage = ModelStorage()
        self.acquisition = Self.makeAcquisition(modelStatus: self.modelStatus, storage: self.storage)
        super.init()
    }

    /// Explicit initializer accepting both dependencies. Production
    /// composition (in `init()`) constructs the shared store and recorder;
    /// tests pass isolated stores and independent recorders so that
    /// `~/Library/Application Support/VoiceDock/Diagnostics/model-launch.jsonl`
    /// and the production preference suite are never touched from the test
    /// process. The recorder is captured eagerly so every AppDelegate recorder
    /// call routes through this single injection point.
    init(preferenceStore: ASRPreferenceStore, launchRecorder: ModelLaunchRecorder) {
        self.preferenceStore = preferenceStore
        self.launchRecorder = launchRecorder
        self.modelStatus = ModelStatus(
            preferenceStore: preferenceStore,
            recorder: launchRecorder
        )
        self.storage = ModelStorage()
        self.acquisition = Self.makeAcquisition(modelStatus: self.modelStatus, storage: self.storage)
        super.init()
    }

    /// Test-only initializer for composition behavior tests.
    /// Allows injecting isolated ModelStorage and a counting coordinator factory
    /// so tests can assert exactly-once construction without real provider load.
    /// The factory runs on MainActor; its closure must be side-effect-free
    /// and deterministic. Production code must never call this initializer.
    init(
        preferenceStore: ASRPreferenceStore,
        launchRecorder: ModelLaunchRecorder,
        storage: ModelStorage,
        coordinatorFactory: @escaping @MainActor () -> SessionCoordinator?
    ) {
        self.preferenceStore = preferenceStore
        self.launchRecorder = launchRecorder
        self.modelStatus = ModelStatus(
            preferenceStore: preferenceStore,
            recorder: launchRecorder
        )
        self.storage = storage
        self.acquisition = Self.makeAcquisition(modelStatus: self.modelStatus, storage: storage)
        super.init()
        self.testCoordinatorFactory = coordinatorFactory
    }

    /// Test-only hook to override makeCoordinator. Only set by the test initializer above.
    private var testCoordinatorFactory: (@MainActor () -> SessionCoordinator?)?

    /// Test-only flag to force production initialization even when VOICEDOCK_TEST_MODE=1.
    /// Used by AppDelegateCompositionTests which run in the test bundle process
    /// (which inherits the test host's environment).
    internal var forceProductionInitialization = false

    /// Test-only accessor for the coordinator (used by composition tests).
    /// Production code must not depend on this.
    internal var testCoordinator: SessionCoordinator? {
        return coordinator
    }

    /// Test-only accessor for the acquisition controller (used by composition tests).
    /// Production code must not depend on this.
    internal var testAcquisition: ModelAcquisitionController {
        return acquisition
    }

    /// Internal makeCoordinator used by startRuntimeIfNeeded.
    /// Production path calls the real factory; test path uses injected factory.
    private func makeCoordinator() -> SessionCoordinator? {
        if let testFactory = testCoordinatorFactory {
            return testFactory()
        }
        // Production path (unchanged)
        writeUIDiagnostic("creating_audioCapture")
        let audioCapture = AudioCapture()
        writeUIDiagnostic("creating_asrProvider")
        let factoryResult = ASRProviderFactory.createProviderWithMetadata(from: preferenceStore)
        let asrProvider = factoryResult.provider

        let resolvedModelDirectory: String
        if let storage = asyncModelStorageDirectory(for: factoryResult.descriptor) {
            resolvedModelDirectory = storage
        } else {
            resolvedModelDirectory = "unknown"
        }

        writeUIDiagnostic("creating_transcriptDestination")
        let transcriptDestination = TranscriptDestination()
        writeUIDiagnostic("creating_coordinator")
        let coord = SessionCoordinator(
            audioCapture: audioCapture,
            asrProvider: asrProvider,
            transcriptDestination: transcriptDestination
        )
        writeUIDiagnostic("coordinator_created")
        modelStatus.captureActive(factoryResult)

        launchRecorder.recordFactoryResult(
            selection: factoryResult.selection,
            descriptorRepoID: factoryResult.descriptor.repoID,
            resolvedModelDirectory: resolvedModelDirectory,
            activeAfterCapture: modelStatus.activeModel
        )
        return coord
    }

    /// Build the UI-facing acquisition controller over the hardened
    /// `ModelInstaller`/`ModelStorage` backend. Downloading a model never
    /// changes the selected/active model (`ModelStatus`), so this shares only
    /// the unchanged selection source.
    private static func makeAcquisition(
        modelStatus: ModelStatus,
        storage: ModelStorage
    ) -> ModelAcquisitionController {
        return ModelAcquisitionController(
            installer: ModelInstaller(storage: storage),
            storage: storage,
            modelStatus: modelStatus
        )
    }

    // Explicit termination state machine
    enum TerminationState {
        case idle
        case pending(cleanupStarted: Bool, timeoutArmed: Bool)
        case replied
    }
    private var terminationState: TerminationState = .idle

    // Expose hotKeyManager for diagnostics
    var hotKeyManagerForDiagnostics: HotKeyManager? {
        return hotKeyManager
    }

    var permissionRefreshReasonForTests: PermissionManager.RefreshReason {
        permissions.lastRefreshReason
    }

    /// Read-only identity of the preference store the no-argument init bound
    /// this AppDelegate to. Surfaced for the deterministic host-isolation tests
    /// so they can assert the host AppDelegate (constructed by
    /// `@NSApplicationDelegateAdaptor` before any XCTest runs) bound itself to
    /// the isolated test-host suite, not the production
    /// `com.voicedock.app.asr-prefs` domain. No setter; no resetForTesting.
    internal var composedPreferenceSuiteName: String {
        preferenceStore.suiteName
    }

    /// Read-only identity of the per-launch recorder the no-argument init bound
    /// this AppDelegate to. Surfaced for the deterministic host-isolation tests
    /// so they can assert the host AppDelegate writes diagnostics under a
    /// temporary `NSTemporaryDirectory()` path, never the canonical production
    /// diagnostics directory. No setter; no resetForTesting.
    internal var composedRecorderOutputDirectory: String {
        launchRecorder.outputDirectoryForDiagnostics.path
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")

        // P2-1 Fix: Clean up stale diagnostic logs from previous crashed session
        cleanupDiagnosticFiles()
        permissions.refresh(reason: .applicationLaunch)

        // Clear and initialize UI diagnostics file
        writeUIDiagnostic("=== VoiceDock UI Diagnostics Start ===")
        writeUIDiagnostic("launch_time=\(Date())")
        writeUIDiagnostic("main_thread=\(Thread.isMainThread)")

        // Check for benchmark mode (VOICEDOCK_BENCHMARK_MODE=1)
        let env = ProcessInfo.processInfo.environment
        let benchmarkMode = env["VOICEDOCK_BENCHMARK_MODE"] == "1"
        writeUIDiagnostic("benchmark_mode=\(benchmarkMode)")

        if benchmarkMode {
            logger.info("Benchmark mode detected - running benchmark instead of normal UI")
            Task { @MainActor in
                await runBenchmarkMode(environment: env)
            }
            return
        }

        // Check for self-test mode
        let selfTestMode = ProcessInfo.processInfo.arguments.contains("--self-test-popover")
        writeUIDiagnostic("self_test_mode=\(selfTestMode)")

        // P1 Fix: Listen for application activation to refresh permission state
        installActivationObserverIfNeeded()

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

    @objc public func applicationDidBecomeActive(_ notification: Notification) {
        // P1 Fix: Refresh permission state when app becomes active
        // This ensures UI updates after user returns from System Settings
        handleApplicationDidBecomeActive()
    }

    private func handleApplicationDidBecomeActive() {
        logger.info("applicationDidBecomeActive - refreshing permissions")
        refreshPermissions(reason: .applicationDidBecomeActive)
    }

    func installActivationObserverIfNeeded() {
        guard activationObserver == nil else { return }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleApplicationDidBecomeActive()
            }
        }
        activationObserverInstallCount += 1
    }

    private func fullInitialize(selfTestMode: Bool) async {
        writeUIDiagnostic("fullInitialize_started")

        // TEST_HOST guard: when running as the Xcode test host
        // (VOICEDOCK_TEST_MODE=1, selected by VoiceDockRuntimeComposition),
        // the host app must NOT construct the production coordinator,
        // Qwen3ASRProvider, or ModelStorage. The prior behavior performed a
        // real ~1.5 GB model load and MLX warmup inside every `xcodebuild
        // test` run (~37 minutes) and could write tokenizer artifacts into
        // the owner's production model directory. The test bundle constructs
        // its own coordinators with injected mocks; the host exists only to
        // host XCTest and the minimal app shell. Production launches never
        // set VOICEDOCK_TEST_MODE and are unaffected.
        // Tests that explicitly set forceProductionInitialization bypass this guard.
        if VoiceDockRuntimeComposition.current.isTestHost && !forceProductionInitialization {
            writeUIDiagnostic("fullInitialize_skipped_test_host")
            logger.info("Test host detected; skipping production coordinator/provider initialization")
            // Still wire the popover with nil coordinator for test host UI
            wirePopover(coordinator: nil)
            return
        }

        // Wire the popover ONCE with a stable CoordinatorBox.
        // The box starts with nil coordinator and gets updated when runtime starts.
        writeUIDiagnostic("wirePopover_initial_start")
        wirePopover(coordinator: nil)
        writeUIDiagnostic("wirePopover_initial_done")

        // 2b) Microphone permission
        checkMicrophonePermission()

        // 2c) Accessibility permission
        refreshPermissions(reason: .applicationLaunch)

        // Wire acquisition completion handler
        self.acquisition.onInstalled = { [weak self] model in
            self?.handleModelInstalled(model)
        }

        // Refresh model availability asynchronously (non-blocking).
        Task { @MainActor in
            await self.modelStatus.refreshAvailability()
        }

        // 2d) Record the executable hash (best-effort, off the launch path).
        // The per-launch terminal diagnostic record is finalized exactly
        // once via the Combine sink on coordinator.state installed when
        // the real coordinator is constructed:
        //   .ready            → finalizeAndFlush(.complete)
        //   .failed(message)  → finalizeAndFlush(.loadFailed/.warmupFailed)
        // and a guaranteed `applicationWillTerminate` flush covers the
        // case where the app terminates before a terminal state is
        // reached (`finalizeAndFlush(.incomplete)`).
        launchRecorder.recordExecutableHash(ModelLaunchRecorder.computeExecutableHash())

        // Initial check: is the selected model valid?
        await checkAndStartRuntime()

        // Run self-test if requested
        if selfTestMode {
            writeUIDiagnostic("Scheduling self-test in 1 second...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await runPopoverSelfTest()
        }
    }

    /// Check the selected model's validity and start the runtime if valid.
    /// Called at launch and after authoritative install completion.
    /// Runs on MainActor; the coordinator == nil guard + MainActor serialization
    /// is the start-admission authority (no separate `started` flag needed).
    private func checkAndStartRuntime() async {
        // Snapshot the current selection before the async validity check.
        let snapshot = modelStatus.selectedModel

        // Authoritative validity check.
        let valid = await storage.isModelValid(snapshot.modelDescriptor)

        // After the await, RECHECK that selection hasn't changed.
        // An async validity result for an obsolete selection must not create a runtime.
        guard modelStatus.selectedModel == snapshot else {
            writeUIDiagnostic("checkAndStartRuntime: selection changed during validity check; aborting")
            return
        }

        // If valid and coordinator is still nil, start the runtime exactly once.
        // MainActor serialization + coordinator != nil is the dedup authority.
        if valid && coordinator == nil {
            await startRuntimeIfNeeded()
        } else if !valid {
            writeUIDiagnostic("checkAndStartRuntime: model invalid (missing/invalid) - coordinator remains nil")
        }
    }

    /// Start the speech runtime when prerequisites are met.
    /// Precondition: called on MainActor, coordinator == nil, model valid.
    private func startRuntimeIfNeeded() async {
        guard coordinator == nil else { return }

        writeUIDiagnostic("startRuntimeIfNeeded: constructing coordinator")
        guard let newCoordinator = makeCoordinator() else {
            writeUIDiagnostic("startRuntimeIfNeeded: makeCoordinator returned nil")
            return
        }
        self.coordinator = newCoordinator

        // Update the stable CoordinatorBox with the new coordinator
        coordinatorBox?.update(coordinator: newCoordinator)

        writeUIDiagnostic("coordinator_assigned")
        installHotKey(against: newCoordinator)
        writeUIDiagnostic("installHotKey_done")
        logger.info("Coordinator wired; status=\(String(describing: newCoordinator.state))")
        writeUIDiagnostic("coordinator_wiring_complete")

        // Exactly-once terminal finalizer driven by the coordinator's
        // published state. The provider already records load and warmup
        // outcomes into the same shared recorder; this sink translates a
        // terminal coordinator state into one `finalizeAndFlush(_:)`.
        // Because the recorder's `hasFlushed` guard is exactly-once, the
        // guaranteed terminate-time flush is a no-op if a terminal flush
        // already fired (and vice-versa).
        lifecycleFinalizerCancellable = newCoordinator.$state.sink { [weak self] state in
            guard let self = self else { return }
            self.handleCoordinatorStateForLaunchDiagnostics(state)
        }
    }

    /// Handle authoritative install completion from ModelAcquisitionController.
    /// Fires only for successful, validated, non-cancelled, non-stale installs.
    private func handleModelInstalled(_ model: ASRModelSelection) {
        // A. Only the currently selected model matters.
        guard model == modelStatus.selectedModel else {
            writeUIDiagnostic("handleModelInstalled: installed model \(model.rawValue) != selected \(modelStatus.selectedModel.rawValue); ignoring")
            return
        }

        // B-C. Snapshot selection and revalidate authoritatively.
        let snapshot = modelStatus.selectedModel
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            let valid = await self.storage.isModelValid(snapshot.modelDescriptor)

            // D. After await, RECHECK selection still matches.
            guard self.modelStatus.selectedModel == snapshot else {
                self.writeUIDiagnostic("handleModelInstalled: selection changed during revalidation; aborting")
                return
            }

            // E. If valid and coordinator is nil, start the runtime.
            if valid && self.coordinator == nil {
                await self.startRuntimeIfNeeded()
            }
            // F. If coordinator already exists, DO NOTHING.
            // An existing .failed coordinator belongs to the genuine runtime-failure domain.
            // Do not reinterpret it as model-acquisition recovery.
            else if self.coordinator != nil {
                self.writeUIDiagnostic("handleModelInstalled: coordinator already exists (state=\(String(describing: self.coordinator?.state))); no action")
            }
        }
    }

    /// Translate one observed `SessionCoordinator.State` into the
    /// exactly-once per-launch diagnostic finalization. Caller owns nothing
    /// else; this method only invokes `launchRecorder` (never
    /// `ModelLaunchRecorder.shared`) and the recorder's own exactly-once
    /// guard makes redundant terminal-state flushes no-ops.
    ///
    /// Mapping:
    /// - `.starting`, `.loadingModel`, `.recording-equivalents` (e.g.
    ///   `.waitingForMicrophonePermission`, `.waitingForAccessibility`,
    ///   `.listening`, `.transcribing`, `.delivering`): no finalization — the
    ///   process is still in flight.
    /// - `.idle`: never finalize `.complete` merely because the coordinator
    ///   has reached idle. An `.idle` reached via `cleanup()` during an
    ///   early quit (before load+warmup finished) and any test path that
    ///   constructed the coordinator without a real provider must leave the
    ///   record unfinalized; the guaranteed `applicationWillTerminate` flush
    ///   records the truthful `.incomplete` witness.
    /// - `.ready`: finalize `.complete` only when
    ///   `launchRecorder.shouldFinalizeComplete() == true` (the recorder has
    ///   observed a successful provider load AND a successful warmup).
    /// - `.failed(message)`: finalize with the recorder-derived failure
    ///   phase (`launchRecorder.failureTerminalState()`) so the row records
    ///   `.loadFailed` or `.warmupFailed` rather than the generic
    ///   `.incomplete` family.
    /// - Subsequent finalization attempts are absorbed by the recorder's
    ///   `hasFlushed` exactly-once guard (the terminate-time flush remains
    ///   a guarantee on its own).
    internal func handleCoordinatorStateForLaunchDiagnostics(_ state: SessionCoordinator.State) {
        switch state {
        case .starting,
             .waitingForMicrophonePermission,
             .waitingForAccessibilityPermission,
             .loadingModel,
             .listening,
             .transcribing,
             .delivering,
             .cleaningUp,
             .idle:
            // No finalization. `.idle` is reached via cleanup() on early
            // exit before load+warmup finished, or on any no-ASR / test
            // path; it does NOT prove a successful load+warmup cycle, so
            // it must not finalize `.complete`. The guaranteed terminate
            // flush will record the truthful `.incomplete` witness.
            return
        case .ready:
            // Only finalize `.complete` when the recorder has actually
            // observed a successful provider load AND warmup. The
            // recorder's exactly-once guard keeps a later terminate
            // flush a no-op when this guard fires.
            if launchRecorder.shouldFinalizeComplete() {
                launchRecorder.finalizeAndFlush(.complete)
            }
        case .failed(let message):
            let phase = launchRecorder.failureTerminalState()
            launchRecorder.finalizeAndFlush(phase, reason: message)
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
        writeUIDiagnostic("statusItem_created=true")

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

    private func wirePopover(coordinator: SessionCoordinator?) {
        writeUIDiagnostic("wirePopover_start coordinator=\(coordinator == nil ? "nil" : "present")")

        // Create the stable CoordinatorBox on first call.
        // Subsequent calls just update the coordinator reference.
        if coordinatorBox == nil {
            coordinatorBox = CoordinatorBox(coordinator: coordinator)
            let rootView = MenuBarView(coordinatorBox: coordinatorBox!, permissions: permissions, modelStatus: modelStatus, acquisition: acquisition)
            let controller = NSHostingController(rootView: rootView)

            writeUIDiagnostic("content_view_controller_created=true")

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
        } else {
            // Update the existing CoordinatorBox - this triggers SwiftUI refresh
            // without recreating the popover or its view hierarchy.
            coordinatorBox?.update(coordinator: coordinator)
            writeUIDiagnostic("coordinatorBox_updated coordinator=\(coordinator == nil ? "nil" : "present")")
        }
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
                let granted = await permissions.requestMicrophone()
                logger.info("Microphone prompt result: \(String(describing: granted))")
                self.refreshPermissions(reason: .microphoneRequestCompletion)
            }
        case .granted:
            logger.info("Microphone already granted")
        case .denied:
            logger.info("Microphone denied; status bar will show permission row")
        }
    }

    private func refreshPermissions(reason: PermissionManager.RefreshReason) {
        permissions.refresh(reason: reason)
        writeUIDiagnostic("accessibility_trusted=\(permissions.accessibilityStatus)")
        ensureHotKeyRegisteredIfTrusted()
    }

    func requestAccessibilityFromUserAction() {
        _ = permissions.requestAccessibilityIfNeeded()
        refreshPermissions(reason: .accessibilityRequest)
    }

    private func ensureHotKeyRegisteredIfTrusted() {
        guard permissions.accessibilityStatus else { return }
        guard let coordinator else { return }
        guard hotKeyManager?.registrationStatus != "success" else { return }

        logger.info("Accessibility trusted; ensuring hotkey is registered")
        hotKeyManager?.unregister()
        installHotKey(against: coordinator)
    }

    /// Resolve the canonical model directory for a descriptor on a background
    /// task without blocking the main actor. Returns nil if the synchronous
    /// helper itself fails (e.g. applicationSupportDirectory unavailable).
    private func asyncModelStorageDirectory(for descriptor: QwenModelDescriptor) -> String? {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = supportDir
            .appendingPathComponent("VoiceDock", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(descriptor.canonicalDirectoryName, isDirectory: true)
        return dir.path
    }

    private func installHotKey(against coordinator: SessionCoordinator) {
        // HotKeyManager callbacks now weakly capture self and resolve coordinator at event time
        // Fix: Use explicit result contract - only set hasPressed if startRecording returns true
        let manager = HotKeyManager(
            onStart: { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Only accept if not already pressed AND recording starts successfully
                    if !self.hasPressed {
                        let accepted = self.coordinator?.startRecording() ?? false
                        if accepted {
                            self.hasPressed = true
                        }
                    }
                }
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Only stop if we accepted a press
                    if self.hasPressed {
                        self.hasPressed = false
                        self.coordinator?.stopRecording()
                    }
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
        // AppKit selector trampolines are not a reliable place to assert the
        // current Swift executor. Schedule onto MainActor instead.
        Task { @MainActor [weak self] in
            self?.togglePopoverOnMainActor()
        }
    }

    private func togglePopoverOnMainActor() {
        writeUIDiagnostic("togglePopover_called")
        writeUIDiagnostic("main_thread=\(Thread.isMainThread)")
        refreshPermissions(reason: .popoverWillOpen)

        menuClickCount += 1
        statusItem?.button?.title = "🎙︎\(menuClickCount)"
        logger.info("Menu click count: \(self.menuClickCount)")
        writeUIDiagnostic("menu_click_count=\(menuClickCount)")

        guard let button = statusItem?.button else {
            writeUIDiagnostic("toggle_failed_button_nil")
            logger.error("togglePopover: button is nil")
            return
        }

        writeUIDiagnostic("button_exists=true")
        writeUIDiagnostic("button_window_exists=\(button.window != nil)")
        writeUIDiagnostic("button_frame=\(button.bounds)")

        guard let popover = popover else {
            writeUIDiagnostic("toggle_failed_popover_nil")
            logger.error("togglePopover: popover is nil")
            return
        }

        writeUIDiagnostic("popover_exists=true")

        guard popover.contentViewController != nil else {
            writeUIDiagnostic("toggle_failed_content_controller_nil")
            logger.error("togglePopover: contentViewController is nil")
            return
        }

        writeUIDiagnostic("content_view_controller_exists=true")
        writeUIDiagnostic("popover_is_shown_before=\(popover.isShown)")
        writeUIDiagnostic("popover_content_size=\(popover.contentSize)")

        if popover.isShown {
            popover.performClose(nil)
            writeUIDiagnostic("popover_performClose_called")
            writeUIDiagnostic("popover_closed=true")
            logger.info("Popover closed")
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        writeUIDiagnostic("activate_ignoring_other_apps_called")

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        writeUIDiagnostic("popover_show_called")
        writeUIDiagnostic("popover_is_shown_after=\(popover.isShown)")

        if let popoverWindow = popover.contentViewController?.view.window {
            writeUIDiagnostic("popover_window_frame=\(popoverWindow.frame)")
            writeUIDiagnostic("popover_window_isVisible=\(popoverWindow.isVisible)")
            writeUIDiagnostic("popover_window_isKeyWindow=\(popoverWindow.isKeyWindow)")
        }

        logger.info("Popover opened")
    }

    // MARK: - Diagnostic Test Endpoint
    @objc nonisolated private func handleDiagnosticTest(_ notification: Notification) {
        let action = (notification.userInfo?["action"] as? String) ?? ""
        Task { @MainActor [weak self] in
            self?.handleDiagnosticTestOnMainActor(action: action)
        }
    }

    private func handleDiagnosticTestOnMainActor(action: String) {
        writeUIDiagnostic("DIAGNOSTIC_TEST: \(action)")

        switch action {
        case "press":
            hotKeyManager?.simulatePress()
            writeUIDiagnostic("SIMULATE_PRESS_INVOKED")
        case "release":
            hotKeyManager?.simulateRelease()
            writeUIDiagnostic("SIMULATE_RELEASE_INVOKED")
        default:
            break
        }
    }

    // MARK: - Benchmark Mode

    private func runBenchmarkMode(environment: [String: String]) async {
        writeUIDiagnostic("=== BENCHMARK_MODE_START ===")

        // Validate required environment variables
        guard let modelID = environment["VOICEDOCK_ASR_MODEL"] else {
            writeUIDiagnostic("ERROR: VOICEDOCK_ASR_MODEL not set")
            logger.error("Benchmark mode requires VOICEDOCK_ASR_MODEL environment variable")
            NSApp.terminate(nil)
            return
        }

        guard let fixturesPath = environment["VOICEDOCK_BENCHMARK_FIXTURES"] else {
            writeUIDiagnostic("ERROR: VOICEDOCK_BENCHMARK_FIXTURES not set")
            logger.error("Benchmark mode requires VOICEDOCK_BENCHMARK_FIXTURES environment variable")
            NSApp.terminate(nil)
            return
        }

        guard let manifestPath = environment["VOICEDOCK_BENCHMARK_MANIFEST"] else {
            writeUIDiagnostic("ERROR: VOICEDOCK_BENCHMARK_MANIFEST not set")
            logger.error("Benchmark mode requires VOICEDOCK_BENCHMARK_MANIFEST environment variable")
            NSApp.terminate(nil)
            return
        }

        guard let outputPath = environment["VOICEDOCK_BENCHMARK_OUTPUT"] else {
            writeUIDiagnostic("ERROR: VOICEDOCK_BENCHMARK_OUTPUT not set")
            logger.error("Benchmark mode requires VOICEDOCK_BENCHMARK_OUTPUT environment variable")
            NSApp.terminate(nil)
            return
        }

        writeUIDiagnostic("model=\(modelID)")
        writeUIDiagnostic("fixtures=\(fixturesPath)")
        writeUIDiagnostic("manifest=\(manifestPath)")
        writeUIDiagnostic("output=\(outputPath)")

        // Create parent directory for output if needed
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputDir = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        do {
            // Use shared BenchmarkCore for real inference
            let core = BenchmarkCore()
            let report = try await core.runBenchmark(
                modelID: modelID,
                fixturesPath: fixturesPath,
                manifestPath: manifestPath,
                outputPath: outputPath
            )

            writeUIDiagnostic("BENCHMARK_COMPLETE")
            writeUIDiagnostic("completed_fixtures=\(report.completedFixtures)")
            writeUIDiagnostic("failed_fixtures=\(report.failedFixtures)")
            writeUIDiagnostic("run_duration=\(String(format: "%.2f", report.runDuration))s")

            logger.info("Benchmark complete: \(report.completedFixtures)/\(report.totalFixtures) fixtures processed")
            logger.info("Results written to: \(outputPath)")

        } catch {
            writeUIDiagnostic("BENCHMARK_FAILED: \(error.localizedDescription)")
            logger.error("Benchmark failed: \(error.localizedDescription)")
        }

        // Exit after benchmark completes
        writeUIDiagnostic("=== BENCHMARK_MODE_END ===")
        NSApp.terminate(nil)
    }

    // MARK: - Lifecycle

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("applicationShouldTerminate")
        writeUIDiagnostic("applicationShouldTerminate called")

        switch terminationState {
        case .idle:
            // Record menu-click timestamp if this was a menu-initiated termination
            menuClickTimestamp = Date()
            writeUIDiagnostic("menu_click_timestamp_recorded")

            // Transition to pending state
            terminationState = .pending(cleanupStarted: true, timeoutArmed: true)
            writeUIDiagnostic("state_transition: idle → pending")

            // Begin coordinator cleanup exactly once
            logger.info("Starting coordinator cleanup...")
            writeUIDiagnostic("coordinator_cleanup_start")
            coordinator?.cleanup()

            // Also cleanup hotkey_manager
            hotKeyManager?.unregister()

            // Cleanup is synchronous for termination purposes:
            // - audioCapture.cancel() is synchronous
            // - asrProvider.unload() is fire-and-forget (no need to await)
            // - hotKeyManager.unregister() is synchronous
            // So we can immediately call completeTermination() which replies to AppKit
            writeUIDiagnostic("cleanup_completed_synchronously")

            // Atomically transition to replied and call reply handler
            terminationState = .replied
            logger.info("Termination state: pending → replied (reason: cleanupFinished)")
            writeUIDiagnostic("state_transition: pending → replied")

            // Call exactly once: NSApplication.shared.reply(toApplicationShouldTerminate: true)
            writeUIDiagnostic("calling_termination_reply_handler")
            NSApplication.shared.reply(toApplicationShouldTerminate: true)

            // Return .terminateLater to let AppKit proceed after reply
            writeUIDiagnostic("returning_terminateLater")
            return .terminateLater

        case .pending(_, _):
            // Already pending: do not start duplicate cleanup or timeout
            logger.info("Termination already pending, returning .terminateLater")
            writeUIDiagnostic("termination_already_pending")
            return .terminateLater

        case .replied:
            // Already replied: never send a second reply
            logger.info("Termination already replied, returning .terminateLater")
            writeUIDiagnostic("termination_already_replied")
            return .terminateLater
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("applicationWillTerminate")
        writeUIDiagnostic("applicationWillTerminate")

        // Final, synchronous, idempotent cleanup only
        // Do NOT initiate termination or wait indefinitely
        coordinator?.cleanup()
        hotKeyManager?.unregister()

        // Guaranteed flush of the per-launch diagnostic record so the file is
        // a faithful witness even if the deferred flush from
        // fullInitialize has not yet fired.
        launchRecorder.flush()

        // P1 Fix: Remove notification observer
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        // P2-1 Fix: Clean up temporary diagnostic log files
        cleanupDiagnosticFiles()

        writeUIDiagnostic("=== VoiceDock UI Diagnostics End ===")
    }

    private func cleanupDiagnosticFiles() {
        let paths = [
            uiDiagnosticsPath,
            "/tmp/voicedock-runtime-diagnostics.log",
            "/tmp/voicedock-permission-diagnostics.log"
        ]

        for path in paths {
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.removeItem(at: url)
        }
        logger.info("Diagnostic files cleaned up")
    }
}

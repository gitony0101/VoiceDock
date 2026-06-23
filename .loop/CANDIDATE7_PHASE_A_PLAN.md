# Candidate 7 Phase A Implementation Plan

## Source Analysis

### Character Counter Location

**File:** `VoiceDockApp/UI/MenuBarView.swift:25-29`

```swift
if let transcript = coordinator.currentTranscript {
    Text("\(transcript.count) chars")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

The character counter is in the title HStack at the top of the popover. It displays the transcript length whenever a transcript exists.

**Removal:** Delete lines 25-29 entirely. The `coordinator.currentTranscript` property remains used by the "Last transcript" section (lines 156-167), so no other code depends on this.

### Bottom Label Truncation Source

**File:** `VoiceDockApp/UI/MenuBarView.swift:174-208`

Current layout uses an HStack with Spacers between 6 buttons:

```swift
HStack {
    Button("Open Mic Settings") { ... }
    Spacer()
    Button("Open Acc. Settings") { ... }
    Spacer()
    Button("Show Diagnostics") { ... }
    Spacer()
    Button("Retry") { ... }
    Spacer()
    Button("Refresh Permissions") { ... }
    Spacer()
    Button("Quit") { ... }
}
```

At `font(.caption)` with fixed frame width (340), these labels truncate to "Op...", "Sho...", "Refr...".

**Solution:** Redesign into a cleaner layout with:
- Primary row: Retry, Refresh, More (3 buttons)
- More menu (popover or dropdown) containing:
  - Open Microphone Settings
  - Open Accessibility Settings
  - Show Diagnostics
  - Quit VoiceDock

### Current Paste and Return Coupling

**File:** `VoiceDockCore/Sources/TranscriptDestination.swift:30-52`

```swift
public func paste(text: String, sendReturn: Bool = true) {
    // ... clipboard copy ...
    
    // Simulate Cmd-V paste
    postKeyboardEvent(0x09, .maskCommand)
    
    if sendReturn {
        postKeyboardEvent(0x24, [])
    }
}
```

Currently, `sendReturn` defaults to `true`. The `SessionCoordinator.deliver(text:)` method calls `paste(text:)` without arguments, so Return is always sent.

### Current Preference Storage

**No persistent preference storage exists.** The `TranscriptDestination.paste(sendReturn:)` method has a hardcoded default of `true`. There is no user-configurable setting for:
- Automatic paste toggle
- Return-after-paste toggle
- Terminal safety suppression

### Current Frontmost-App Detection

**Not implemented.** No code currently detects the frontmost application bundle identifier.

### Current Keyboard-Event Synthesis

**File:** `VoiceDockCore/Sources/TranscriptDestination.swift:54-65`

```swift
private static func postKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { ... }
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
```

Uses `CGEvent` with `kCGHIDEventTap` for post. 0x09 = 'V' key (Cmd-V paste), 0x24 = Return.

## Proposed Architecture

### New Types

```swift
// VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift
public struct TranscriptDeliveryPreferences {
    public var automaticPaste: Bool
    public var sendReturnAfterPaste: Bool
    
    public init(automaticPaste: Bool = true, sendReturnAfterPaste: Bool = false)
}

// VoiceDockCore/Sources/FrontmostApplicationProviding.swift
public protocol FrontmostApplicationProviding {
    var frontmostBundleIdentifier: String? { get }
}

// VoiceDockCore/Sources/TerminalApplicationClassifier.swift
public struct TerminalApplicationClassifier {
    public static let knownTerminals: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        // Warp: needs verification
    ]
    
    public static func isTerminal(bundleId: String?) -> Bool
}

// VoiceDockCore/Sources/TranscriptDeliveryPolicy.swift
public struct TranscriptDeliveryPolicy {
    public let preferences: TranscriptDeliveryPreferences
    public let appProvider: FrontmostApplicationProviding
    
    public func determineDelivery() -> TranscriptDeliveryDecision
}

// VoiceDockCore/Sources/TranscriptDeliveryDecision.swift
public enum TranscriptDeliveryDecision {
    case copyToClipboard
    case pasteTranscript
    case pasteAndSendReturn
    case pasteWithReturnSuppressed(reason: String)
}
```

### Preference Storage

Use `UserDefaults` with explicit keys:

```swift
// VoiceDockCore/Sources/TranscriptDeliveryPreferences.swift
extension TranscriptDeliveryPreferences {
    public static var standard: TranscriptDeliveryPreferences {
        get {
            let defaults = UserDefaults.standard
            return TranscriptDeliveryPreferences(
                automaticPaste: defaults.object(forKey: "automaticPaste") as? Bool ?? true,
                sendReturnAfterPaste: defaults.object(forKey: "sendReturnAfterPaste") as? Bool ?? false
            )
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.automaticPaste, forKey: "automaticPaste")
            defaults.set(newValue.sendReturnAfterPaste, forKey: "sendReturnAfterPaste")
        }
    }
}
```

### SessionCoordinator Integration

Update `SessionCoordinator.deliver(text:)`:

```swift
private func deliver(text: String?) async {
    state = .delivering
    if let text = text, !text.isEmpty {
        let policy = TranscriptDeliveryPolicy(
            preferences: .standard,
            appProvider: NSWorkspace.shared // or custom provider
        )
        let decision = policy.determineDelivery()
        
        switch decision {
        case .copyToClipboard:
            transcriptDestination?.copyToClipboard(text: text)
        case .pasteTranscript:
            transcriptDestination?.paste(text: text, sendReturn: false)
        case .pasteAndSendReturn:
            transcriptDestination?.paste(text: text, sendReturn: true)
        case .pasteWithReturnSuppressed(let reason):
            transcriptDestination?.paste(text: text, sendReturn: false)
            logger.info("Return suppressed: \(reason)")
        }
        
        currentTranscript = text
    }
    state = .ready
}
```

### UI for Settings

Add to `MenuBarView.swift`:

```swift
// In the More menu popover
Toggle("Automatically paste transcript", isOn: $automaticPaste)
Toggle("Press Return after paste", isOn: $sendReturnAfterPaste)
```

## Expected Files to Change

### Core (VoiceDockCore/Sources/)

1. **New:** `TranscriptDeliveryPreferences.swift`
2. **New:** `FrontmostApplicationProviding.swift`
3. **New:** `TerminalApplicationClassifier.swift`
4. **New:** `TranscriptDeliveryPolicy.swift`
5. **New:** `TranscriptDeliveryDecision.swift`
6. **Modify:** `TranscriptDestination.swift` - add `copyToClipboard` method, support preference-driven behavior
7. **Modify:** `SessionCoordinator.swift` - integrate policy, call `copyToClipboard` when paste disabled

### UI (VoiceDockApp/)

8. **Modify:** `MenuBarView.swift` - remove char counter, redesign bottom action area, add More menu, add settings toggles
9. **Modify:** `AppDelegate.swift` - if preference access needed at app level

### Tests (VoiceDockAppTests/)

10. **New:** `TranscriptDeliveryPreferencesTests.swift`
11. **New:** `TerminalApplicationClassifierTests.swift`
12. **New:** `TranscriptDeliveryPolicyTests.swift`
13. **Modify:** `TranscriptDestinationTests.swift` - test `copyToClipboard` method
14. **Modify:** `SessionCoordinatorTests.swift` - test preference-driven delivery behavior

## Test Strategy

### Unit Tests

1. **TranscriptDeliveryPreferencesTests**
   - Default values (paste=ON, return=OFF)
   - Persistence via UserDefaults
   - Independent mutations (changing paste doesn't affect return)

2. **TerminalApplicationClassifierTests**
   - Known terminal bundle IDs recognized
   - Non-terminals rejected
   - Warp bundle ID verified

3. **TranscriptDeliveryPolicyTests**
   - All 4 decision outcomes tested
   - Terminal safety suppression verified
   - Preference interactions correct

4. **TranscriptDestinationTests**
   - `copyToClipboard` updates NSPasteboard
   - Paste disabled still updates clipboard

5. **SessionCoordinatorTests**
   - Paste OFF → clipboard only
   - Return OFF → no Return event
   - Both ON → paste + Return
   - Terminal detection → Return suppressed

### Integration Tests (if feasible)

- Mock frontmost app provider
- Verify event-sending behavior with mocked Accessibility

## Migration Strategy

### Candidate 6 Users

Candidate 6 has no preference storage. On first launch of Candidate 7:

- `automaticPaste` defaults to `true` (matches Candidate 6 behavior)
- `sendReturnAfterPaste` defaults to `false` (NEW - safer)

This is intentional: Candidate 6's hardcoded `sendReturn=true` was identified as a safety issue (terminal execution risk). The default change is a deliberate safety improvement.

### UserDefaults Keys

```
automaticPaste: Bool (default: true)
sendReturnAfterPaste: Bool (default: false)
```

## Supported Terminal Bundle Identifiers

**Confirmed:**
- `com.apple.Terminal` - Apple Terminal
- `com.googlecode.iterm2` - iTerm2

**To Verify:**
- Warp - needs investigation (may use `dev.warp.Warp` or similar)

## Review Procedure

1. Create `.loop/CANDIDATE7_PHASE_A_PLAN.md` (this document)
2. Implement core types (preferences, classifier, policy)
3. Update `TranscriptDestination` and `SessionCoordinator`
4. Redesign `MenuBarView` UI
5. Add comprehensive tests
6. Run `swift build`, `swift test`
7. Run `xcodebuild` Debug/Release builds and tests
8. Create review build at `build/candidate-7-phase-a-review/VoiceDock.app`
9. Create owner review document
10. Commit and push to `feat/candidate7-release-polish`

## Non-Goals (Phase A)

- Branding/icon updates (Phase B)
- Model management UI
- VAD or automatic endpointing
- Partial streaming transcripts
- AI assistant features
- Conversation history
- TTS
- Signing/notarization
- Performance optimization
- Multi-language UI

## Known Gaps from Phase A Spec

The following Phase A requirements cannot be fully addressed without owner interaction:

1. **Warp bundle ID verification** - requires Warp installation
2. **Physical microphone testing** - requires owner
3. **Icon source handling** - Phase B, do not modify
4. **Actual paste/Return behavior verification** - requires owner physical test

These will be documented honestly in the owner review instructions.
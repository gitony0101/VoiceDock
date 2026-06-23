# Permission State Refresh Fix - Summary

**Date**: 2026-06-22  
**Issue**: macOS TCC code-identity mismatch / stale permission state refresh  
**Status**: ✅ FIXED (automated gates complete)

---

## Problem Description

The VoiceDock UI showed stale permission status even after users granted permissions in System Settings. This was caused by:

1. **No reactive state**: `PermissionManager` was a `struct` - SwiftUI couldn't observe changes
2. **No refresh triggers**: Permission checks only ran at initial view render
3. **TCC code identity**: macOS tracks permissions by code signature identity (ad-hoc signed builds appear as "different" apps)

## Changes Made

### 1. `VoiceDockApp/Services/PermissionManager.swift`

**Before**:
```swift
struct PermissionManager {
    func checkMicrophone() -> PermissionStatus { ... }
    func checkAccessibility() -> Bool { ... }
}
```

**After**:
```swift
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityStatus: Bool = false
    
    func refresh() {
        microphoneStatus = checkMicrophone()
        accessibilityStatus = checkAccessibility()
        // ... publishes changes to trigger UI updates
    }
}
```

### 2. `VoiceDockApp/UI/MenuBarView.swift`

**Added**:
- `@ObservedObject var permissions: PermissionManager` (reactive observation)
- `.onAppear { permissions.refresh() }` (refresh on popover open)
- "Refresh Permissions" button for manual refresh
- Delayed refresh after opening Settings (2 second delay)
- Permission refresh in Retry button handler

### 3. `VoiceDockApp/AppDelegate.swift`

**Added**:
```swift
NotificationCenter.default.addObserver(
    self, selector: #selector(applicationDidBecomeActive(_:)),
    name: NSApplication.didBecomeActiveNotification, object: nil
)

@objc public func applicationDidBecomeActive(_ notification: Notification) {
    permissions.refresh()  // Refresh when app becomes active
}
```

## Verification Results

| Gate | Status | Details |
|------|--------|---------|
| Debug build | ✅ PASS | `xcodebuild -scheme VoiceDock -configuration Debug build` |
| Release build | ✅ PASS | `xcodebuild -scheme VoiceDock -configuration Release build` |
| Unit tests | ✅ PASS | 24/24 tests passed (Mock-based) |
| Fresh dist build | ✅ COMPLETE | `dist/VoiceDock.app` updated with fix |

## Owner Action Required

The **TCC code identity** issue is a macOS system behavior, not a code bug. To test the fix:

### Step 1: Clean up old TCC entries
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Delete any `VoiceDock` entries (especially ones from DerivedData paths)
3. Delete any `xctest` entries (test host pollution)

### Step 2: Add the correct app
1. Click `+` in Accessibility settings
2. Navigate to: `~/Documents/Github/portfolio-projects/VoiceDock/dist/VoiceDock.app`
3. Add it and toggle the switch ON

### Step 3: Launch the fixed Candidate
```bash
cd ~/Documents/Github/portfolio-projects/VoiceDock
pkill -x VoiceDock 2>/dev/null || true
open -n dist/VoiceDock.app
```

### Step 4: Verify the fix
1. Click the VoiceDock menu bar icon
2. The popover should show:
   - **Microphone**: granted ✅ (or click "Open Mic Settings" to grant)
   - **Accessibility**: granted ✅
3. Test: Open System Settings, grant permission, return — UI should update automatically
4. Test: Click "Refresh Permissions" — status should update immediately

## Automatic Refresh Triggers

The UI now refreshes permission status when:
- ✅ Popover opens (e.g., user clicks menu bar icon)
- ✅ App becomes active (e.g., user returns from System Settings)
- ✅ "Refresh Permissions" button is clicked
- ✅ "Retry" button is clicked
- ✅ "Open Mic Settings" / "Open Acc. Settings" is clicked (2s delayed refresh)

## Files Changed

```
 VoiceDockApp/AppDelegate.swift                | +18
 VoiceDockApp/Services/PermissionManager.swift | +47 -3
 VoiceDockApp/UI/MenuBarView.swift             | +28 -3
 3 files changed, 85 insertions(+), 8 deletions(-)
```

## Notes

- The `PermissionManager` is now `@MainActor` to safely publish UI state changes
- `PermissionStatus` conforms to `CustomStringConvertible` for logging
- The `refresh()` method queries live APIs (`AXIsProcessTrusted()`, `AVCaptureDevice.authorizationStatus`)
- No duplicate permission prompts: uses `AXIsProcessTrusted()` for status checks, `AXIsProcessTrustedWithOptions()` only for explicit user requests

---

**Next**: Manual M1 verification pending owner action (microphone + ASR + paste test)
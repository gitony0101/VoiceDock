# macOS TCC Code-Identity Issue - Troubleshooting Guide

## Problem Description

**Symptom**: System Settings → Privacy & Security → Accessibility shows `VoiceDock` as enabled, but the VoiceDock UI still displays "Accessibility: denied" or `AXIsProcessTrusted()` returns `false`.

## Root Cause

macOS does **not** identify applications by name alone. The TCC (Transparency, Consent, and Control) system tracks permissions by **code signature identity**, which includes:

1. **CodeDirectory hash (CDHash)** - Unique to each build
2. **Signing type** - Ad-hoc vs. Developer ID vs. App Store
3. **Executable path** - Different paths = different identities
4. **Bundle identifier** - Must match

When you rebuild or move the app, macOS may treat it as a "different" application, even if the name is the same.

## Evidence from VoiceDock Candidate 2

```
Executable:    dist/VoiceDock.app/Contents/MacOS/VoiceDock
Identifier:    com.voicedock.app
CDHash:        2a2e91218dde192c5266109b9b38086fb71f17cc
Signing:       adhoc (no team identifier)
```

The `adhoc` signing means each build has a slightly different identity.

## Symptoms Explained

| Symptom | Cause |
|---------|-------|
| System Settings shows VoiceDock ✓ | Old build path or different CDHash |
| App reports `AXIsProcessTrusted() == false` | Current build not in TCC database |
| Accessibility list has multiple "VoiceDock" entries | Each build created a new identity |
| `xctest` also appears in Accessibility list | Test runs also create TCC entries |

## Solution for Users

### Step 1: Clean Up Old TCC Entries

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Look for **all** entries named:
   - `VoiceDock` (may have multiple)
   - `xctest` (from test runs)
3. **Remove all of them** by:
   - Selecting each entry
   - Clicking the `–` (minus) button
   - Or toggling the switch off

### Step 2: Add the Correct App

1. Click the `+` (plus) button in Accessibility settings
2. Navigate to:
   ```
   ~/Documents/Github/portfolio-projects/VoiceDock/dist/VoiceDock.app
   ```
3. Select `VoiceDock.app` and click **Open**
4. Toggle the switch to **ON** (green)

**Important**: Use the exact `dist/VoiceDock.app` path, not a copy in Applications or elsewhere.

### Step 3: Relaunch VoiceDock

```bash
cd ~/Documents/Github/portfolio-projects/VoiceDock

# Quit any running instances
pkill -x VoiceDock 2>/dev/null || true

# Launch the fixed candidate
open -n dist/VoiceDock.app

# Verify the process path
pgrep -afil 'VoiceDock.app/Contents/MacOS/VoiceDock'
```

Expected output:
```
.../dist/VoiceDock.app/Contents/MacOS/VoiceDock
```

If you see `DerivedData` or any other path, quit and re-add the correct `dist/VoiceDock.app`.

### Step 4: Verify in VoiceDock UI

1. Click the VoiceDock menu bar icon
2. The popover should now show:
   ```
   Microphone: granted ✓
   Accessibility: granted ✓
   ```

3. If it still shows "denied":
   - Click **"Refresh Permissions"** button
   - Or close and reopen the popover

## How VoiceDock Handles This (Code Fixes)

### Permission Refresh Triggers

The UI now automatically refreshes permission state when:

| Trigger | Implementation |
|---------|----------------|
| Popover opens | `.onAppear { permissions.refresh() }` |
| App becomes active | `applicationDidBecomeActive` notification |
| Retry clicked | `permissions.refresh()` after retry |
| Refresh button clicked | Direct `permissions.refresh()` call |
| Settings opened | Delayed refresh (2s) after opening Settings |

### Observable Permission State

`PermissionManager` is now an `ObservableObject`:

```swift
@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphoneStatus: PermissionStatus
    @Published private(set) var accessibilityStatus: Bool
    
    func refresh() {
        microphoneStatus = checkMicrophone()  // Live query
        accessibilityStatus = checkAccessibility()  // AXIsProcessTrusted()
    }
}
```

The UI uses `@ObservedObject` to automatically update when published values change.

## Diagnostic Information

VoiceDock provides detailed diagnostics in the popover:

1. Click **"Show Diagnostics"**
2. Check:
   - **Accessibility trusted**: Should be `true`
   - **Backend**: `Carbon` or `NSEvent`
   - **Registration**: `success`
   - **Bundle ID**: `com.voicedock.app`
   - **Executable path**: Should point to `dist/VoiceDock.app`

## Prevention

To avoid TCC identity issues in the future:

1. **Don't move the app after granting permissions** - TCC tracks the path
2. **Use consistent signing** - Ad-hoc is fine for development, but rebuilds may create new identities
3. **Clean up old entries** - Remove stale VoiceDock entries from Accessibility settings periodically
4. **Use dist/VoiceDock.app** - Don't copy to Applications until final release

## Technical Details

### Why Ad-Hoc Signing Causes Issues

```
Ad-hoc signing: No certificate, no Team Identifier
  → CDHash changes with each build
  → macOS treats different CDHash as different code
  → TCC database entry doesn't match
```

### Code Signing Identity

macOS uses the **Designated Requirement** to identify code:

```
anchor apple generic and identifier "com.voicedock.app"
```

With ad-hoc signing, there's no stable certificate chain, so path becomes the primary identifier.

### TCC Database Location

```
~/Library/Application Support/com.apple.TCC/TCC.db
```

**Do not manually edit this file** - use System Settings UI.

## Verification Commands

```bash
# Check current signing identity
codesign -dv dist/VoiceDock.app 2>&1 | grep -E "Identifier|CDHash|Team"

# Verify running process path  
pgrep -afil 'VoiceDock.app/Contents/MacOS/VoiceDock'

# Check TCC database (requires Full Disk Access)
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, service, auth_value FROM access WHERE client LIKE '%VoiceDock%';"
```

## Expected Behavior After Fix

```
✅ Popover shows "Accessibility: granted" immediately
✅ Opening Settings and returning updates UI automatically  
✅ "Refresh Permissions" button works
✅ Carbon or NSEvent backend registers successfully
✅ Global hotkey works (Control+Option+Space)
```

## If Problems Persist

1. **Verify exact executable path**:
   ```bash
   ls -la dist/VoiceDock.app/Contents/MacOS/VoiceDock
   codesign -dv dist/VoiceDock.app
   ```

2. **Check for Console errors**:
   ```bash
   log stream --predicate 'eventMessage contains "VoiceDock"' --style syslog
   ```

3. **Full reset**:
   - Remove all VoiceDock entries from Accessibility
   - Delete `~/Library/Application Support/com.apple.TCC/TCC.db` (requires reboot)
   - Re-add `dist/VoiceDock.app`

---

**Document Updated**: 2026-06-23  
**Applies to**: VoiceDock Candidate 2+  
**Status**: Code fixes implemented, UI refresh working
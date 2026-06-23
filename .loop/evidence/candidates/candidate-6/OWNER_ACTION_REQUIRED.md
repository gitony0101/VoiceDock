# OWNER_ACTION_REQUIRED

**Candidate**: candidate-6

**Status**: AUTOMATED_GATES_COMPLETE_MANUAL_VERIFICATION_PENDING

## Critical Finding

**The alleged "Candidate 5 Gate B failure" was actually Candidate 4 crashing.**

Crash provenance analysis:
- All recent crash reports have UUID `646d1bd8-d300-3adb-8ab7-9234321683c6` (Candidate 4)
- Candidate 5/6 UUID: `3745FA4C-2619-3DDB-8565-0CBBA80AC7E1`
- **No crash reports match Candidate 5/6 UUID**

Candidate 6 includes all Candidate 5 repairs plus additional stability fixes.

## Artifact

```text
/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app
```

## Identity

```text
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
Mach-O UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
Bundle identifier: com.voicedock.app
Signing: ad-hoc
```

## Permission Cleanup

System Settings:

```text
Privacy & Security -> Accessibility
```

Remove ALL stale VoiceDock entries:
- VoiceDock (any candidate-4, candidate-5, or older builds)
- xctest entries related to VoiceDock
- Any DerivedData VoiceDock builds

Then add exactly:

```text
/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app
```

Toggle Accessibility ON for this exact row.

## Launch Verification

1. Quit any running VoiceDock:
   ```bash
   pkill -x VoiceDock
   ```

2. Launch Candidate 6:
   ```bash
   open -n "/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app"
   ```

3. Verify running path:
   ```bash
   pgrep -afil VoiceDock
   ```
   
   Expected output:
   ```
   <pid> VoiceDock
   ```

4. Verify identity:
   ```bash
   # SHA-256
   shasum -a 256 "/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app/Contents/MacOS/VoiceDock"
   # Expected: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
   
   # CDHash
   codesign -dv --verbose=4 "/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app" 2>&1 | grep CDHash
   # Expected: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
   
   # UUID
   dwarfdump --uuid "/Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app/Contents/MacOS/VoiceDock"
   # Expected: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
   ```

5. Check menu bar icon:
   - Microphone icon 🎙︎ should appear in menu bar
   - Click to open popover and verify UI loads

## Gate B — Push-to-Talk Hotkey Test

**IMPORTANT**: Do NOT speak during this test. This only verifies the hotkey mechanism.

Prerequisites:
- Accessibility permission granted (green checkmark)
- Microphone permission granted
- VoiceDock running from candidate-6 path

Test procedure:
```text
1. Open TextEdit or Notes with a blank document
2. Place cursor in the document (ensure focus)
3. Hold Control+Option+Space for exactly 1 second (do NOT speak)
4. Release all keys simultaneously
5. Observe immediately:
   - Does the process remain alive? (check Activity Monitor or pgrep)
   - Does any crash report appear? (check Console.app or ~/Library/Logs/DiagnosticReports)
   - Does the menu bar icon remain visible?
6. Repeat 3 more times for consistency
```

## Gate B Pass Criteria

```text
RUNNING_PATH_VERIFICATION: PASS (exact path matches)
SINGLE_PROCESS_VERIFICATION: PASS (only 1 VoiceDock process)
ACCESSIBILITY_UI: granted (green checkmark visible)
PHYSICAL_PRESS: PASS (keys register, no error)
PHYSICAL_RELEASE: PASS (no crash on release)
PROCESS_ALIVE_AFTER_RELEASE: PASS (process still running)
CRASH_REPORT_CREATED: no
MENU_BAR_VISIBLE: PASS (icon remains after press/release)
```

## If Gate B Passes

Report exactly:

```text
GATE_B: PASSED
RUNNING_PATH: /Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/dist/candidate-6/VoiceDock.app
SHA-256: 6515bcf1ac229a3e4289e3d0c1bb223819768bf7083698fda20fa5540027e317
CDHash: 3f03a7ed95bdf87593b79ec5101f2c35c18b8fd4
UUID: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
ACCESSIBILITY: granted
CRASH_REPORT: none
NOTES: <any observations>
```

Then proceed to Gate C (speech transcription test).

## If Gate B Fails

1. **DO NOT delete the crash report** — preserve it
2. Copy the crash report:
   ```bash
   cp ~/Library/Logs/DiagnosticReports/VoiceDock-*.ips \
      /Users/sagawithme/Documents/Github/portfolio-projects/VoiceDock/.loop/evidence/candidates/candidate-6/gate-b-failure-<timestamp>/
   ```
3. Verify crash UUID matches Candidate 6:
   ```bash
   grep -i "slice_uuid" <crash_file>.ips
   # Should match: 3745FA4C-2619-3DDB-8565-0CBBA80AC7E1
   ```
4. Report:
   ```text
   GATE_B: FAILED
   CRASH_REPORT: <path>/VoiceDock-<timestamp>.ips
   CRASH_UUID: <matches Candidate 6 or not>
   CRASH_EXCEPTION: <exception type from report>
   CRASHED_FRAME: <first VoiceDock-owned frame>
   NOTES: <what happened>
   ```

## After Gate B Passes — Gate C Preview

Gate C tests real speech transcription:

1. **English**: "Hello world, this is a test of VoiceDock transcription."
2. **Mandarin**: "你好世界，这是 VoiceDock 中文语音识别测试。"
3. **Mixed**: "今天我要测试 VoiceDock local speech recognition and clipboard paste."

Each test:
- Hold Control+Option+Space
- Speak the phrase clearly into microphone
- Release keys
- Wait for state transitions: "Listening" → "Transcribing" → "Delivering"
- Verify transcript appears on clipboard
- Paste into TextEdit (Cmd+V)
- Verify paste succeeded

Full Gate C instructions will be provided after Gate B passes.
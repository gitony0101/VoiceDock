# VoiceDock

@AGENTS.md

## Current Repository State

VoiceDock now has an active Swift implementation, Swift Package, XcodeGen configuration, generated Xcode project, tests, and an active Smart Ralph specification.

Do not reset the repository, recreate the project from scratch, restore the previously deleted implementation, or repeat completed planning.

The active execution state is under:

* `specs/voicedock-ptt-mvp/`

Before changing product scope or acceptance criteria, read:

* `VOICEDOCK_MASTER_PROMPT.md`

## Build-System Ownership

`project.yml` is the authoritative source for the Xcode project.

After changing Xcode targets, packages, settings, entitlements, Info.plist properties, or schemes:

1. update `project.yml`
2. run `xcodegen generate`
3. verify the regenerated project
4. rerun applicable Xcode builds and tests

Do not manually edit:

* `VoiceDock.xcodeproj/project.pbxproj`
* generated workspace package references
* generated Info.plist content

`Package.swift` may remain as the SwiftPM build and test definition only if it uses the same production sources without maintaining a duplicate implementation.

## Execution Mode

Continue the active Smart Ralph loop automatically.

Do not stop after planning, summaries, scaffolding, compilation milestones, refactoring checkpoints, or partial verification.

For every task:

observe
→ implement
→ verify
→ inspect
→ repair
→ update persisted state
→ continue

Product delivery takes priority over cosmetic refactoring and test-target perfection.

Do not widen scope beyond the Push-to-Talk MVP.

## Verification

A SwiftPM executable is not the final product artifact.

The final product must be a native `VoiceDock.app` built through Xcode.

Do not claim completion until automated checks and required real-device checks have truthful evidence.

If owner interaction is required, finish all remaining automated work first and request only the exact permission or speech test needed.

## Git Mode

Do not push, create a remote, or publish the repository.

During the current autonomous run, do not create new commits unless the owner explicitly enables checkpoint commits.


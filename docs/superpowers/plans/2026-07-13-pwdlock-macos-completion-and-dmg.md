# Pwdlock macOS Completion and DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the macOS MVP security and daily-use flows, verify them, then produce a locally installable ad-hoc-signed DMG.

**Architecture:** Keep security rules and time policy in `PwdlockCore` or `VaultAppState`; SwiftUI only renders state and forwards explicit user actions. Package the SwiftPM executable in a conventional `.app` bundle, embed Homebrew-provided dylibs beneath `Contents/Frameworks`, rewrite their runtime paths to `@rpath`, ad-hoc sign the bundle, and place it in a DMG.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, CryptoKit, SQLCipher, Argon2id, XCTest/Swift Testing, `codesign`, `hdiutil`, `install_name_tool`.

---

### Task 1: Enforce master-password policy and failed-unlock cooldown

**Files:**
- Create: `Sources/PwdlockCore/Application/UnlockRateLimiter.swift`
- Modify: `Sources/PwdlockMacApp/VaultAppState.swift`
- Modify: `Sources/PwdlockMacApp/VaultViews.swift`
- Test: `Tests/PwdlockCoreTests/UnlockRateLimiterTests.swift`
- Test: `Tests/PwdlockMacAppTests/VaultAppStateTests.swift`

- [ ] Write failing tests for twelve-character creation/change rejection, five failures causing a 30-second cooldown, and an injected clock allowing a retry after the cooldown.
- [ ] Run `swift test --filter UnlockRateLimiterTests` and verify failure because the policy type is absent.
- [ ] Implement a process-local limiter with cooldown sequence 30/60/120/300 seconds (capped at 300), and a `VaultAppState` policy check that never invokes Argon2id during cooldown.
- [ ] Add SwiftUI accessible validation and generic cooldown messaging; show the irrecoverability notice on creation and master-password change.
- [ ] Re-run targeted tests, then `swift test`.

### Task 2: Make automatic locking configurable and category navigation usable

**Files:**
- Modify: `Sources/PwdlockMacApp/VaultAppState.swift`
- Modify: `Sources/PwdlockMacApp/VaultViews.swift`
- Test: `Tests/PwdlockMacAppTests/VaultAppStateTests.swift`

- [ ] Write failing tests for selecting 3, 5, and 10-minute lock durations and for category filtering being combined with title search.
- [ ] Run matching tests and verify they fail because the setting/filter API is absent.
- [ ] Implement a `UserDefaults`-backed auto-lock duration constrained to 180/300/600 seconds, recreating/resetting the controller safely; expose distinct categories from the unlocked list and filter items without exposing passwords.
- [ ] Add a compact Settings sheet and category picker in the library side bar.
- [ ] Re-run targeted tests, then `swift test`.

### Task 3: Complete clipboard feedback and pre-package acceptance assets

**Files:**
- Modify: `Sources/PwdlockMacApp/VaultAppState.swift`
- Modify: `Sources/PwdlockMacApp/VaultViews.swift`
- Create: `docs/acceptance/macos-mvp-manual-checklist.md`
- Test: `Tests/PwdlockMacAppTests/VaultAppStateTests.swift`

- [ ] Write failing state test for a copy-expiry countdown and immediate clearing action that does not overwrite newer clipboard content.
- [ ] Run the targeted test to demonstrate the missing state behavior.
- [ ] Implement UI-only countdown metadata driven by the existing 30-second clipboard service and expose a clear-now action; do not read clipboard text back into application state.
- [ ] Write an executable manual checklist covering create, restart/unlock, failed unlock cooldown, editing, background lock, clipboard replacement safety, backup/restore, corrupted backup rejection, and locked-state data hiding.
- [ ] Run `swift test` and inspect the checklist for no untestable security claims.

### Task 4: Build and package a self-contained ad-hoc-signed macOS app

**Files:**
- Create: `platforms/macos/PwdlockMac/Resources/Info.plist`
- Create: `platforms/macos/PwdlockMac/Scripts/build-dmg.sh`
- Create: `platforms/macos/PwdlockMac/Resources/dmg-background.png` only if needed for a conventional Finder layout
- Test: `platforms/macos/PwdlockMac/Scripts/build-dmg.sh` via `hdiutil imageinfo`, `codesign --verify --deep --strict`, and executing the embedded binary with `otool -L` inspection.

- [ ] Write a shell validation sequence that expects an app bundle with an executable, `Info.plist`, embedded `libargon2` and `libsqlcipher`, and valid ad-hoc signature.
- [ ] Run it before creating the script and verify it fails because `Pwdlock.app` does not exist.
- [ ] Implement a deterministic release build script: build release executable, create `.app`, copy dependent dylibs, change dylib IDs/references to `@rpath`, ad-hoc sign nested libraries and app, stage `/Applications` symlink, and create `dist/Pwdlock-macOS.dmg`.
- [ ] Build the DMG; verify the image mounts, bundle signature passes, executable links only to bundled third-party dylibs, and DMG contains the app.
- [ ] Record exact artifact location and known limitation: ad-hoc signing is intended only for user validation and may require Finder’s Open confirmation.


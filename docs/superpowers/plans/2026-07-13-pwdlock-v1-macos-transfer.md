# Pwdlock v1 macOS Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the password-copy layout and let macOS securely export a portable `.pwdlock` file and restore it into a fresh local vault.

**Architecture:** The shared area contains only a versioned protocol document and public test vectors. macOS keeps all codec, KDF, AEAD, file I/O and SwiftUI code within `platforms/macos/PwdlockMac`; export uses an independent password, Argon2id and two AES-256-GCM layers. Import is intentionally restricted to a device with no existing vault, where it creates a fresh Vault Key/local master password and inserts authenticated records transactionally.

**Tech Stack:** Swift 6.2, Foundation, CryptoKit, SQLCipher, Argon2id, Swift Testing, AppKit file panels.

---

### Task 1: Repair copy feedback layout and freeze v1 assets

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift`
- Create: `shared/protocol/pwdlock-v1.md`
- Create: `shared/test-vectors/pwdlock-v1/README.md`

- [ ] Add a SwiftUI structural regression or source verifier that ensures the copy status/action are in a compact leading-aligned password subview, not separated by a spacer.
- [ ] Run the verifier against the existing view and confirm the old layout fails its stated invariant.
- [ ] Replace the full-width status `HStack` with a leading-aligned stack beneath the password controls; retain countdown and clear action behavior.
- [ ] Document exact binary field order, AAD, KDF limits, payload schema, unified error semantics, and new-vault-only import scope.
- [ ] Verify UI tests and protocol document consistency.

### Task 2: Implement and test the macOS `.pwdlock` v1 codec

**Files:**
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Transfer/PwdlockArchive.swift`
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Transfer/PwdlockPayload.swift`
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift`
- Test: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/PwdlockArchiveTests.swift`

- [ ] Write failing tests for deterministic encode/decode round-trip, wrong export password, tampered header/tag, truncation/trailing bytes, KDF and payload-size limits.
- [ ] Run the focused suite and confirm failures because codec symbols are absent.
- [ ] Implement fixed-header parsing before allocation, NFC password input, Argon2id KDF, random Export Key, AES-GCM wrapping/payload encryption with specified AAD, authentication-before-JSON parsing, strict JSON schema limits, and uniform authentication errors.
- [ ] Add session export that reads all login records, writes a temporary `.pwdlock`, fsyncs, re-decrypts/validates, then atomically publishes it.
- [ ] Re-run focused tests and the full suite.

### Task 3: Restore a `.pwdlock` file into a fresh local vault

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift`
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift`
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift`
- Test: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/PwdlockArchiveTests.swift`
- Test: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift`

- [ ] Write failing tests for importing an exported file into an empty directory and unlocking its records with the newly selected local master password; assert an existing vault is never overwritten.
- [ ] Run the focused test and confirm failure before the import API exists.
- [ ] Implement temporary decode/validation, then fresh vault creation and a single SQLCipher transaction for imported records; on any failure remove only temporary files and preserve existing vault files.
- [ ] Add Chinese export-password/confirmation sheet, macOS save panel, and first-launch import option with file picker, export password and local master password fields; expose generic errors and a success summary.
- [ ] Verify export → clean target import → restart/unlock round trip and all regressions.


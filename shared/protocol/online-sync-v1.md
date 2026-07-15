# Pwdlock online sync v1

This protocol defines the opaque data boundary between a Pwdlock client and the sync service. It is deliberately independent of UI and backend implementation.

## Scope

- The server authenticates an account and authorizes Vault ownership.
- Password-vault contents are encrypted and authenticated on the client before upload.
- The server stores and returns encrypted envelopes unchanged.
- A client decrypts, verifies, orders, merges, and resolves conflicts locally.

## Key hierarchy

1. A client generates a random 256-bit Vault Key using the platform CSPRNG.
2. A vault master password is NFC-normalized, UTF-8 encoded, and passed to Argon2id with a random salt and persisted KDF parameters.
3. The Argon2id output is a Key Encryption Key (KEK), used only to encrypt the Vault Key envelope.
4. HKDF-SHA-256 derives context-separated keys from the Vault Key, including `pwdlock.sync.v1.change` and `pwdlock.sync.v1.signing`.
5. A local Touch ID wrapping key is device-local and is never synchronized.

## Cryptographic algorithms

| Purpose | Algorithm |
|---|---|
| Password KDF | Argon2id |
| AEAD | AES-256-GCM with a unique random 96-bit nonce |
| Key separation | HKDF-SHA-256 |
| Change signature | Ed25519 |
| Randomness | Platform CSPRNG |

Implementations must use audited platform/library primitives. They must not implement AES, GCM, Argon2, HKDF, or Ed25519 themselves.

## Encrypted Vault Key envelope

The client uploads a base64-encoded canonical binary envelope. It contains protocol version, Argon2id parameters, salt, nonce, AES-GCM ciphertext, and tag. The plaintext is exactly the 32-byte Vault Key. The server treats this as opaque.

## Encrypted change envelope

The client uploads `changeId`, `ciphertext`, and `signature` as base64 strings. The encrypted plaintext contains every password-record field, operation type, revision, tombstone state, previous-change digest, and conflict metadata. No password business field is sent outside ciphertext.

AES-GCM additional authenticated data is the canonical UTF-8 byte sequence:

```text
pwdlock.sync.v1 | vaultId | changeId
```

The device public key is a raw 32-byte Ed25519 key encoded as base64. The signature is a raw 64-byte Ed25519 signature encoded as base64. It signs the exact UTF-8 bytes of `pwdlock.sync.v1`, a NUL byte, `vaultId`, a NUL byte, `changeId`, a NUL byte, and the base64 ciphertext. The server verifies it before storing a change. A client rejects invalid authentication tags, signatures, impossible revisions, repeated IDs, and broken predecessor links before applying a change.

## Server-visible metadata

The server may hold account IDs, Vault IDs, device IDs, opaque change IDs, server cursor IDs, ciphertext sizes, and transport timestamps. It must never require plaintext credential fields. Clients should pad payloads in a future protocol version if ciphertext-size leakage is in scope.

## Password change and recovery

Changing a vault master password re-encrypts only the Vault Key envelope. There is no server-side recovery of a forgotten vault master password. Account recovery grants sync-service access only; it cannot decrypt the password vault.

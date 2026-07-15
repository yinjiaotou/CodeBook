# Pwdlock online sync v1 test vectors

This directory will contain deterministic, non-secret interoperability vectors for the online encrypted-envelope protocol. Every vector must state the exact algorithm identifiers, byte encoding, key, salt, nonce, AAD, plaintext, ciphertext, tag, signature input, and expected rejection behavior.

The first implementation gate requires vectors for:

- AES-256-GCM encryption/decryption using the exact `pwdlock.sync.v1` AAD encoding;
- Argon2id-derived KEK and Vault Key envelope opening;
- HKDF context separation for Vault Key subkeys;
- Ed25519 change-signature verification;
- rejected altered ciphertext, tag, signature, Vault ID, change ID, predecessor digest, replayed ID, and broken predecessor link.

Only synthetic test keys, test passwords, and fake credential records may be committed here. No production ciphertext, real account identifier, Vault Key, Touch ID material, or password is permitted.

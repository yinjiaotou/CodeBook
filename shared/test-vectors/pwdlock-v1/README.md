# Pwdlock v1 test vectors

This directory is reserved for publicly safe, byte-level `.pwdlock` v1 interoperability vectors. No binary vectors are published yet.

Planned vectors use fixed, explicitly non-secret inputs: a documented test export password, fixed Argon2id parameters within the v1 accepted range, fixed salts/nonces, a fixed synthetic Export Key, and synthetic JSON records. They will never contain a real password, vault key, credential, personal URL, or production archive.

Each future vector will state the exact header bytes, AAD slices, plaintext JSON bytes, derived-key expectation where safe to publish, ciphertext/tag expectation, and expected result. Coverage will include:

- canonical successful decrypt/parse with v1 creation parameters;
- accepted boundary KDF parameters and rejected below/above-range parameters;
- altered magic, version, algorithm IDs, flags, reserved bytes, lengths, truncation, and trailing bytes;
- altered wrap or payload ciphertext/tag, and a wrong export password;
- payload UTF-8, JSON-schema, duplicate-ID, record-count, text-size, tombstone, and conflict-group failures;
- physical archive, ciphertext, and decrypted-payload resource limits.

Expected failures are classified as fixed-container rejection, resource-limit rejection, unified **“password incorrect or file corrupted”** authentication failure, or post-authenticated payload-schema rejection. Implementations must authenticate before JSON parsing and must not expose decrypted content or a more specific authentication cause.

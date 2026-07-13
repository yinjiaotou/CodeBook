# Pwdlock v1 portable archive

This document defines the runtime- and platform-neutral `.pwdlock` v1 archive. The archive carries encrypted data only; it is not a database format and never contains a local vault key or local master password.

## Encoding and cryptography

- All multibyte integers are unsigned big-endian (network byte order).
- Passwords and every JSON text value are Unicode NFC-normalized, then UTF-8 encoded. Invalid UTF-8 and NUL (`U+0000`) are rejected.
- `kdfId = 0x01` is Argon2id (RFC 9106-compatible, version 1.3), with a 16-byte salt and a 32-byte output.
- `aeadId = 0x01` is AES-256-GCM. Every nonce is exactly 12 bytes, every authentication tag is exactly 16 bytes, and a nonce must never repeat for the same key.
- V1 exports use `memoryKiB = 65536`, `iterations = 3`, and `parallelism = 1`. V1 importers accept only `65536...262144` KiB, `3...10` iterations, and `1...4` lanes (inclusive); any other value is rejected before running the KDF. Implementations must not silently lower parameters.

## Binary container

The fixed header is 116 bytes. Fields occur in exactly this order:

| Offset | Field | Length | Required value / meaning |
|---:|---|---:|---|
| 0 | `magic` | 4 | ASCII `PWLK` (`50 57 4c 4b`) |
| 4 | `formatVersion` | 1 | `0x01` |
| 5 | `kdfId` | 1 | `0x01` (Argon2id) |
| 6 | `aeadId` | 1 | `0x01` (AES-256-GCM) |
| 7 | `flags` | 1 | `0x00` |
| 8 | `memoryKiB` | 4 | Argon2id memory cost |
| 12 | `iterations` | 4 | Argon2id time cost |
| 16 | `parallelism` | 1 | Argon2id lanes |
| 17 | `reserved` | 3 | all zero |
| 20 | `passwordSalt` | 16 | export-password salt |
| 36 | `wrapNonce` | 12 | nonce for wrapping the Export Key |
| 48 | `wrappedExportKey` | 32 | AES-GCM ciphertext of the 32-byte Export Key |
| 80 | `wrapTag` | 16 | tag for `wrappedExportKey` |
| 96 | `payloadNonce` | 12 | nonce for the JSON payload |
| 108 | `payloadLength` | 8 | payload-ciphertext byte length |
| 116 | `payloadCiphertext` | `payloadLength` | encrypted UTF-8 JSON |
| final | `payloadTag` | 16 | payload tag |

`payloadLength` excludes `payloadTag`. Reject a file unless its exact size is `116 + payloadLength + 16`; trailing bytes and truncation are invalid. The archive file is at most 100 MiB (104,857,600 bytes), and `payloadLength` is at most 100 MiB. Check both the physical size and the fixed header before allocating payload-sized buffers.

Derive the 32-byte export KEK from the NFC UTF-8 export password and `passwordSalt`. Decrypt `wrappedExportKey` with AES-256-GCM using this exact AAD: header bytes at offsets `0..<36` (through and including `passwordSalt`). Decrypt `payloadCiphertext` with the recovered Export Key using this exact AAD: header bytes at offsets `0..<116` (through and including `payloadLength`, `wrappedExportKey`, and `wrapTag`). No JSON representation, native structure layout, or platform-default text encoding may substitute for these bytes.

## Authenticated payload

Only parse JSON after both GCM operations authenticate. The plaintext is UTF-8 JSON, at most 200 MiB (209,715,200 bytes) after decryption. Its top-level object has exactly these required members:

```json
{
  "schemaVersion": 1,
  "exportId": "lowercase-rfc4122-uuid",
  "sourceVaultId": "lowercase-rfc4122-uuid",
  "createdAtMs": 1760000000000,
  "records": [],
  "tombstones": [],
  "conflictGroups": []
}
```

Unknown, missing, duplicate, or wrongly typed members are invalid. `schemaVersion` is the JSON integer `1`. UUIDs are lowercase RFC 4122 text. Timestamps are non-negative UTC Unix milliseconds. Revisions are integers in `0...9007199254740991` so every supported JSON implementation can represent them exactly. Arrays may be empty, but the combined number of records, tombstones, and conflict variants must not exceed 100,000; reject duplicate record IDs and any record ID that also appears as a tombstone.

Each `records` entry has exactly these members:

```json
{
  "id": "uuid", "type": "login", "title": "…", "username": "…",
  "password": "…", "url": "…", "category": "…", "note": "…",
  "createdAtMs": 1760000000000, "updatedAtMs": 1760000000000,
  "revision": 0, "deviceId": "uuid"
}
```

`type` is only `login`; `createdAtMs <= updatedAtMs`. After NFC normalization, `title` contains 1...256 Unicode scalars; `username`, `url`, and `category` each contain at most 2,048; `password` at most 4,096; and `note` at most 16,384.

Each `tombstones` entry has exactly `recordId` (UUID), `deletedAtMs` (timestamp), `revision` (revision), and `deviceId` (UUID).

Each `conflictGroups` entry has exactly `groupId` (UUID), `recordId` (UUID), `state` (`"pending"`), `createdAtMs` (timestamp), and `variants` (array). A group has 2...10 variants and represents unresolved alternatives for its `recordId`. Every variant has exactly `kind`, `sourceVaultId`, and one matching object:

- `kind: "record"` requires `record`, which is a complete valid record, and forbids `tombstone`.
- `kind: "tombstone"` requires `tombstone`, which is a complete valid tombstone, and forbids `record`.

## Validation, errors, and import scope

Perform fixed-header, version, reserved-byte, size, and KDF-bound checks before expensive allocation or KDF work. Authenticate the Export Key and payload before parsing JSON. Validate the complete authenticated schema and limits before writing local data.

At the user boundary, wrong export password, changed authenticated header/ciphertext/tag, truncation that reaches authentication, and authentication failures all return one indistinguishable error: **“password incorrect or file corrupted.”** Do not reveal which key, tag, field, or parse location failed. Unsupported version/algorithm, invalid fixed header, resource-limit violations, and post-authenticated schema violations may be reported as a generic unsupported/invalid archive error without exposing decrypted content. Never log passwords, keys, plaintext, or detailed authentication failures.

V1 macOS initial import is only permitted when the local vault is empty: no local vault metadata and no local database exist. It creates a new local vault under a newly selected local master password after archive authentication and schema validation. If a vault already exists, macOS rejects the import without changing it; it performs no silent merge, overwrite, or partial import. This is an application scope rule, not a property of the archive bytes.

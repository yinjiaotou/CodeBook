CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "loginName" VARCHAR(320) NOT NULL UNIQUE,
  "passwordHash" VARCHAR(512) NOT NULL
);

CREATE TABLE IF NOT EXISTS vaults (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "encryptedKeyEnvelope" TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS vaults_owner_id_idx ON vaults ("ownerId");

CREATE TABLE IF NOT EXISTS devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "ownerId" UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "publicSigningKey" VARCHAR(64) NOT NULL,
  label VARCHAR(120) NOT NULL,
  "revokedAt" TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS devices_owner_id_idx ON devices ("ownerId");

CREATE TABLE IF NOT EXISTS vault_changes (
  sequence BIGSERIAL PRIMARY KEY,
  "vaultId" UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
  "changeId" VARCHAR(128) NOT NULL UNIQUE,
  "deviceId" UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
  ciphertext TEXT NOT NULL,
  signature TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS vault_changes_vault_sequence_idx ON vault_changes ("vaultId", sequence);

-- SN-41A.3.2C: Durable artist write identity foundation.
--
-- A receipt identifies the last successful guarded mutation.
-- The receipt is valid for recovery only while the current
-- server_revision equals last_write_server_revision.
--
-- These columns are intentionally nullable for existing artists.
-- This migration does not activate recovery or modify RPCs.

ALTER TABLE public.artists
    ADD COLUMN last_write_outbox_id text,
    ADD COLUMN last_write_mutation_revision bigint,
    ADD COLUMN last_write_server_revision bigint;

ALTER TABLE public.artists
    ADD CONSTRAINT artists_write_receipt_consistency
    CHECK (
        (
            last_write_outbox_id IS NULL
            AND last_write_mutation_revision IS NULL
            AND last_write_server_revision IS NULL
        )
        OR
        (
            last_write_outbox_id IS NOT NULL
            AND length(trim(last_write_outbox_id)) > 0
            AND last_write_mutation_revision IS NOT NULL
            AND last_write_mutation_revision >= 1
            AND last_write_server_revision IS NOT NULL
            AND last_write_server_revision >= 1
        )
    );

-- No direct client permissions are granted for these fields.
-- Existing row-level security and table privileges remain in effect.
--
-- The subsequent guarded RPC migration must:
--   1. Accept the outbox ID and mutation revision.
--   2. Atomically record the receipt with the artist write.
--   3. Return an explicit replay outcome when the same write
--      has already succeeded and the server revision still matches.
--   4. Reject different identities without overwriting cloud data.
package sqlite

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite/seeds"
)

// Seed reconciliation sentinel errors (metadata-only taxonomy; never embed row
// payloads or paths). Fail-closed semantics: the state machine rejects
// checksum, state, and read-back digest anomalies before or without any write.
var (
	// ErrCatalogSeedChecksum is returned when the embedded SQL body's SHA-256
	// does not match its declared metadata, before any write.
	ErrCatalogSeedChecksum = errors.New("catalog seed checksum failed")
	// ErrCatalogSeedState is returned when the existing seed-owned state cannot
	// be reconciled (a newer seed version, or registry-version drift at the
	// same ordinal). The apply fails closed before any mutation.
	ErrCatalogSeedState = errors.New("catalog seed state rejects apply")
	// ErrCatalogSeedDigest is returned when the seed version matches but the
	// active catalog digest does not match the committed dataset (drift), or
	// when the post-apply read-back digest does not match. Never auto-repairs.
	ErrCatalogSeedDigest = errors.New("catalog seed read-back digest mismatch")
)

// ApplyCatalogSeed executes the embedded System Property Registry full-state
// seed and reconciles seed-owned rows atomically. The whole operation — SQL
// SHA-256 gate, state classification, SQL execution, tombstone reconciliation,
// and exact read-back digest verification — runs inside ONE top-level
// Store.WithinTx, so any failure rolls back to the pre-call logical state.
//
// The embedded SQL obtains the WorkspaceID from workspace_metadata.singleton =
// 1; no Registry JSON is read at runtime and no WorkspaceID is substituted into
// the SQL.
func (store *Store) ApplyCatalogSeed(ctx context.Context, wsctx domainentry.WorkspaceContext) error {
	return store.applyCatalogSeedMeta(ctx, wsctx, seeds.Current())
}

// applyCatalogSeedMeta is the testable seam: it runs the state machine against
// explicit seed metadata (so tests can inject a tampered hash or a partial SQL
// body) inside a single top-level WithinTx.
func (store *Store) applyCatalogSeedMeta(ctx context.Context, wsctx domainentry.WorkspaceContext, meta seeds.SeedMetadata) error {
	return store.WithinTx(ctx, func(tx *gorm.DB) error {
		return applyCatalogSeedInTx(tx, wsctx, meta)
	})
}

// seedOutcome is the result of classifying the existing seed-owned state.
type seedOutcome int

const (
	// seedOutcomeApply means the state is fresh or older: execute the seed SQL
	// and reconcile seed-owned rows.
	seedOutcomeApply seedOutcome = iota
	// seedOutcomeNoOp means the seed version and digest already match: success
	// with no write.
	seedOutcomeNoOp
)

// applyCatalogSeedInTx runs the transactional seed state machine on a
// transaction-scoped *gorm.DB. Order: SQL SHA-256 gate, read the SEED-OWNED
// state, classify (fresh/older -> apply; same+digest -> no-op; drift/mixed/
// newer -> fail closed), then apply + reconcile + seed read-back digest
// verification, all before the enclosing transaction commits. State and digest
// are scoped to seed_owner = system_property_registry rows only, because
// preserved NULL-seed user/provider rows are never part of the seed dataset
// digest.
func applyCatalogSeedInTx(tx *gorm.DB, wsctx domainentry.WorkspaceContext, meta seeds.SeedMetadata) error {
	// SQL SHA-256 gate BEFORE any write.
	if sha256Hex(meta.SQLBody) != meta.SQLSHA256 {
		return ErrCatalogSeedChecksum
	}

	// Read the current seed-owned state (before mutation) through the tx handle.
	defs, descs, bindings, terms, err := loadSeedRows(tx, wsctx)
	if err != nil {
		return err
	}
	snapshot, err := assembleSnapshot(defs, descs, bindings, terms)
	if err != nil {
		return err
	}
	seedState, err := deriveSeedState(defs, descs, bindings, terms)
	if err != nil {
		return err
	}
	currentSeedDigest, err := catalogDigest(snapshot)
	if err != nil {
		return err
	}

	outcome, err := classifySeedState(seedState, currentSeedDigest, meta)
	if err != nil {
		return err
	}
	if outcome == seedOutcomeNoOp {
		return nil
	}

	// Apply: execute the embedded seed SQL, then reconcile seed-owned rows.
	if err := tx.Exec(meta.SQLBody).Error; err != nil {
		return err
	}
	if err := reconcileSeedOwned(tx, wsctx.ID.Bytes(), meta); err != nil {
		return err
	}

	// Exact seed read-back + digest verification BEFORE the enclosing commit. If
	// the post-apply seed catalog does not match the committed dataset digest,
	// the whole transaction rolls back.
	afterDefs, afterDescs, afterBindings, afterTerms, err := loadSeedRows(tx, wsctx)
	if err != nil {
		return err
	}
	afterSnapshot, err := assembleSnapshot(afterDefs, afterDescs, afterBindings, afterTerms)
	if err != nil {
		return err
	}
	afterDigest, err := catalogDigest(afterSnapshot)
	if err != nil {
		return err
	}
	if hexEncode(afterDigest[:]) != meta.DatasetSHA256 {
		return ErrCatalogSeedDigest
	}
	return nil
}

// classifySeedState maps the existing seed state to an apply/no-op outcome,
// failing closed for drift, newer, or registry-version drift at the same
// ordinal. deriveSeedState already rejected mixed tuples and zero-binding seed
// state before this is reached.
func classifySeedState(state SeedState, digest [32]byte, meta seeds.SeedMetadata) (seedOutcome, error) {
	if !state.HasSeed {
		// All four seed-owned sets empty -> fresh apply.
		return seedOutcomeApply, nil
	}
	switch {
	case state.Version < meta.SeedOrdinal:
		// One older consistent tuple -> apply upgrade.
		return seedOutcomeApply, nil
	case state.Version > meta.SeedOrdinal:
		return seedOutcomeApply, fmt.Errorf("%w: newer seed version %d", ErrCatalogSeedState, state.Version)
	case state.SourceVersion != meta.SystemRegistryVersion:
		// Same ordinal but a different registry source version -> drift.
		return seedOutcomeApply, fmt.Errorf("%w: seed registry version drift", ErrCatalogSeedState)
	default:
		// Same tuple: no-write iff the active digest matches the dataset.
		if hexEncode(digest[:]) == meta.DatasetSHA256 {
			return seedOutcomeNoOp, nil
		}
		return seedOutcomeApply, ErrCatalogSeedDigest
	}
}

// reconcileSeedOwned tombstones seed-owned rows left over from an OLDER seed
// (their seed tuple differs from the current seed). It touches only
// seed_owner = system_property_registry, never retargets by label/alias, and
// preserves identity (tombstone, never hard delete). Removed Registry
// descriptors tombstone their definition and all bindings; removed native keys
// tombstone their binding/source descriptor.
func reconcileSeedOwned(tx *gorm.DB, wsBytes []byte, meta seeds.SeedMetadata) error {
	owner := seedOwnerSystemPropertyRegistry
	now := time.Now().UTC()
	curVersion := meta.SeedOrdinal
	curSource := meta.SystemRegistryVersion

	// 1. Removed definitions (Registry descriptors): tombstone the definition,
	// then every seed-owned binding referencing it.
	if err := tx.Model(&WorkspacePropertyDefinitionRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND (seed_version IS NOT ? OR seed_source_version IS NOT ?)",
			wsBytes, owner, "active", curVersion, curSource).
		Updates(map[string]any{"lifecycle_state": "tombstoned", "updated_at": now}).Error; err != nil {
		return err
	}
	if err := tx.Model(&PropertyBindingRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND property_id IN (SELECT property_id FROM workspace_property_definitions WHERE workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?)",
			wsBytes, owner, "active", wsBytes, owner, "tombstoned").
		Updates(map[string]any{"lifecycle_state": "tombstoned", "updated_at": now}).Error; err != nil {
		return err
	}

	// 2. Removed source descriptors (native keys): tombstone the descriptor,
	// then every seed-owned binding referencing it.
	if err := tx.Model(&SourcePropertyDescriptorRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND (seed_version IS NOT ? OR seed_source_version IS NOT ?)",
			wsBytes, owner, "active", curVersion, curSource).
		Updates(map[string]any{"lifecycle_state": "tombstoned", "updated_at": now}).Error; err != nil {
		return err
	}
	if err := tx.Model(&PropertyBindingRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND (provider_id, source_instance_id, scope_kind, scope_external_id, external_property_id) IN (SELECT provider_id, source_instance_id, scope_kind, scope_external_id, external_property_id FROM source_property_descriptors WHERE workspace_id = ? AND seed_owner = ? AND lifecycle_state = ?)",
			wsBytes, owner, "active", wsBytes, owner, "tombstoned").
		Updates(map[string]any{"lifecycle_state": "tombstoned", "updated_at": now}).Error; err != nil {
		return err
	}

	// 3. Removed bindings: tombstone any remaining seed-owned active binding
	// whose tuple is not the current seed's (e.g. a removed binding whose
	// definition/source descriptor is still current).
	if err := tx.Model(&PropertyBindingRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND (seed_version IS NOT ? OR seed_source_version IS NOT ?)",
			wsBytes, owner, "active", curVersion, curSource).
		Updates(map[string]any{"lifecycle_state": "tombstoned", "updated_at": now}).Error; err != nil {
		return err
	}
	if err := tx.Model(&WorkspacePropertyTermRow{}).
		Where("workspace_id = ? AND seed_owner = ? AND lifecycle_state = ? AND (seed_version IS NOT ? OR seed_source_version IS NOT ?)",
			wsBytes, owner, "active", curVersion, curSource).
		Updates(map[string]any{"lifecycle_state": "tombstoned"}).Error; err != nil {
		return err
	}

	return nil
}

// sha256Hex returns the lowercase hex SHA-256 of value.
func sha256Hex(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

// hexEncode returns the lowercase hex encoding of b.
func hexEncode(b []byte) string {
	const hexDigits = "0123456789abcdef"
	out := make([]byte, len(b)*2)
	for i, v := range b {
		out[i*2] = hexDigits[v>>4]
		out[i*2+1] = hexDigits[v&0x0f]
	}
	return string(out)
}

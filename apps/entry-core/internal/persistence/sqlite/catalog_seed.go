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
// state, refuse a fully-tombstoned current-seed catalog (fresh misclassification
// would silently reactivate corrupt rows), classify (fresh/older -> apply;
// same+digest -> no-op; drift/mixed/newer -> fail closed), then apply +
// reconcile + seed read-back digest verification, all before the enclosing
// transaction commits. State and digest are scoped to seed_owner =
// system_property_registry rows only, because preserved NULL-seed user/provider
// rows are never part of the seed dataset digest.
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
	// Seed-owned history is classified at every lifecycle regardless of the
	// active set: a newer ordinal or same-ordinal source-version drift must
	// fail closed even when the active current tuple would otherwise be a
	// no-op, and a fully tombstoned current tuple is corruption. Only older
	// tombstoned tuples (normal upgrade leftovers) are allowed through.
	if err := rejectNonFreshSeedHistory(tx, wsctx.ID.Bytes(), meta, seedState.HasSeed); err != nil {
		return err
	}
	// 시드 적용 마커가 무장된 DB에서 active seed 집합과 이력 어느 쪽도 없으면
	// seed-owned row가 물리 삭제된 것이다. fresh 재분류로 시드 SQL을 재실행해
	// 손상을 은닉하는 대신 실패 닫기한다. 이력 분류 뒤에 실행하므로 newer/drift
	// 이력은 여전히 ErrCatalogSeedState로 분류된다.
	marker, err := readCatalogSeedMarker(tx)
	if err != nil {
		return err
	}
	if marker.applied() && !seedState.HasSeed {
		return ErrCatalogSeedStateCorrupt
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
		// no-op 재조정은 마커가 아직 이 튜플을 가리키지 않을 때만(0006 이전
		// DB의 첫 재조정) 마커를 무장한다. 이미 무장됐으면 write 없이 통과한다.
		if marker.matches(meta) {
			return nil
		}
		return writeCatalogSeedMarker(tx, meta)
	}

	if err := reconcileSeedOwned(tx, wsctx.ID.Bytes(), meta); err != nil {
		return err
	}
	if err := tx.Exec(meta.SQLBody).Error; err != nil {
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
	// 적용 성공과 같은 트랜잭션에서 마커를 기록한다. 이 커밋 없이는 마커가
	// 무장되지 않는다.
	return writeCatalogSeedMarker(tx, meta)
}

// catalogSeedMarker는 workspace_metadata에 기록된 시드 적용 마커 상태다.
type catalogSeedMarker struct {
	ordinal       *int
	sourceVersion *string
}

// applied는 마커가 무장되었는지를 나타낸다. 두 컬럼은 항상 함께 기록되므로 둘
// 다 비어 있으면 미적용이다.
func (m catalogSeedMarker) applied() bool {
	return m.ordinal != nil && m.sourceVersion != nil
}

// matches는 마커가 이미 메타데이터의 적용 튜플과 일치하는지를 나타낸다.
func (m catalogSeedMarker) matches(meta seeds.SeedMetadata) bool {
	return m.applied() && *m.ordinal == meta.SeedOrdinal && *m.sourceVersion == meta.SystemRegistryVersion
}

// readCatalogSeedMarker는 workspace_metadata에서 시드 적용 마커를 읽는다.
func readCatalogSeedMarker(tx *gorm.DB) (catalogSeedMarker, error) {
	var row WorkspaceMetadataRow
	if err := tx.Where("singleton = ?", 1).First(&row).Error; err != nil {
		return catalogSeedMarker{}, err
	}
	return catalogSeedMarker{ordinal: row.CatalogSeedOrdinal, sourceVersion: row.CatalogSeedSourceVersion}, nil
}

// writeCatalogSeedMarker는 시드 적용 튜플을 workspace_metadata에 기록한다. 호출
// 시점은 항상 ApplyCatalogSeed 트랜잭션 안이므로 마커와 시드는 원자적으로 함께
// 커밋되거나 함께 롤백된다.
func writeCatalogSeedMarker(tx *gorm.DB, meta seeds.SeedMetadata) error {
	return tx.Model(&WorkspaceMetadataRow{}).
		Where("singleton = ?", 1).
		Updates(map[string]any{
			"catalog_seed_ordinal":        meta.SeedOrdinal,
			"catalog_seed_source_version": meta.SystemRegistryVersion,
		}).Error
}

// rejectNonFreshSeedHistory classifies every seed-owned history tuple at any
// lifecycle, regardless of the active set. A fresh catalog carries no
// seed-owned row at all. History at the CURRENT tuple with an empty active set
// means the catalog was fully tombstoned (corruption). A NEWER ordinal or a
// same-ordinal/different-source tuple means downgrade or drift history that
// classifySeedState's no-op path would otherwise ignore. A NULL seed trio on a
// seed-owned row is corruption. Only strictly older tuples - the tombstones a
// normal upgrade leaves behind - are allowed.
func rejectNonFreshSeedHistory(tx *gorm.DB, wsBytes []byte, meta seeds.SeedMetadata, hasActiveSeed bool) error {
	owner := seedOwnerSystemPropertyRegistry
	families := []any{
		&WorkspacePropertyDefinitionRow{},
		&SourcePropertyDescriptorRow{},
		&PropertyBindingRow{},
		&WorkspacePropertyTermRow{},
	}
	currentTupleSeen := false
	for _, family := range families {
		var tuples []struct {
			SeedVersion       *int
			SeedSourceVersion *string
		}
		if err := tx.Model(family).
			Select("seed_version, seed_source_version").
			Where("workspace_id = ? AND seed_owner = ?", wsBytes, owner).
			Group("seed_version, seed_source_version").
			Scan(&tuples).Error; err != nil {
			return err
		}
		for _, tuple := range tuples {
			if tuple.SeedVersion == nil || tuple.SeedSourceVersion == nil {
				return ErrCatalogSeedStateCorrupt
			}
			switch {
			case *tuple.SeedVersion == meta.SeedOrdinal && *tuple.SeedSourceVersion == meta.SystemRegistryVersion:
				currentTupleSeen = true
			case *tuple.SeedVersion > meta.SeedOrdinal:
				return fmt.Errorf("%w: newer historical seed tuple %d/%s",
					ErrCatalogSeedState, *tuple.SeedVersion, *tuple.SeedSourceVersion)
			case *tuple.SeedVersion == meta.SeedOrdinal && *tuple.SeedSourceVersion != meta.SystemRegistryVersion:
				return fmt.Errorf("%w: historical seed source-version drift %d/%s",
					ErrCatalogSeedState, *tuple.SeedVersion, *tuple.SeedSourceVersion)
			}
		}
	}
	if currentTupleSeen && !hasActiveSeed {
		return ErrCatalogSeedStateCorrupt
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

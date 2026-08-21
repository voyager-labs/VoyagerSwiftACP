package sqlite

import (
	"errors"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// ErrCatalogSeedStateCorrupt marks seed-state corruption detected while reading
// the active catalog: either mixed (seed_version, seed_source_version) tuples
// across the seed-owned rows, or seed-owned rows with zero active seed-owned
// bindings. The load fails closed on either condition.
var ErrCatalogSeedStateCorrupt = errors.New("catalog seed state corrupt")

// SeedState is the derived seed provenance of a loaded catalog. HasSeed is true
// only when every active seed-owned row across all four families shares a
// single (Version, SourceVersion) tuple. mapping_version never participates in
// seed state; only the seed_owner/seed_version/seed_source_version trio does.
type SeedState struct {
	HasSeed       bool
	Version       int
	SourceVersion string
}

// seedTuple is the natural seed provenance pair collected per seed-owned row.
type seedTuple struct {
	version       int
	sourceVersion string
}

// isSeedOwned reports whether a row is an active system seed-owned row. Only
// seed_owner = system_property_registry counts; the mapper already rejected any
// other owner or partial trio, so a fully-populated trio here is well-formed.
func isSeedOwned(owner *string) bool {
	return owner != nil && *owner == seedOwnerSystemPropertyRegistry
}

// deriveSeedState reads the seed provenance across the four loaded active row
// sets and enforces the plan's seed-state contract: all four families empty, or
// exactly one identical tuple everywhere. Zero active seed-owned bindings while
// any other family carries seed-owned rows, and mixed tuples, are corruption.
func deriveSeedState(
	defs []WorkspacePropertyDefinitionRow,
	descs []SourcePropertyDescriptorRow,
	bindings []PropertyBindingRow,
	terms []WorkspacePropertyTermRow,
) (SeedState, error) {
	tuples := make(map[seedTuple]struct{})
	hasAnySeed := false
	hasSeedBinding := false

	collect := func(owner *string, version *int, sourceVersion *string) {
		if !isSeedOwned(owner) {
			return
		}
		hasAnySeed = true
		tuple := seedTuple{version: *version, sourceVersion: *sourceVersion}
		tuples[tuple] = struct{}{}
	}
	for _, row := range defs {
		collect(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion)
	}
	for _, row := range descs {
		collect(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion)
	}
	for _, row := range bindings {
		seedOwned := isSeedOwned(row.SeedOwner)
		if seedOwned {
			hasSeedBinding = true
		}
		collect(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion)
	}
	for _, row := range terms {
		collect(row.SeedOwner, row.SeedVersion, row.SeedSourceVersion)
	}

	if !hasAnySeed {
		return SeedState{}, nil
	}
	// A seed that contributes no active binding cannot reconcile a meaningful
	// catalog; the seed-owned rows without any seed binding are corruption.
	if !hasSeedBinding {
		return SeedState{}, ErrCatalogSeedStateCorrupt
	}
	if len(tuples) != 1 {
		return SeedState{}, ErrCatalogSeedStateCorrupt
	}
	for tuple := range tuples {
		return SeedState{HasSeed: true, Version: tuple.version, SourceVersion: tuple.sourceVersion}, nil
	}
	panic("unreachable")
}

// catalogDigest computes the canonical digest over the active mapped snapshot.
// It intentionally does NOT reimplement framing/hash: it delegates entirely to
// domainentry.PropertyCatalogSnapshot.Digest, which already excludes
// workspace_id/timestamps/tombstoned history and includes identity scheme,
// origin, and every active stable field/term. Persistence never duplicates that
// logic.
func catalogDigest(snapshot domainentry.PropertyCatalogSnapshot) ([32]byte, error) {
	return snapshot.Digest()
}

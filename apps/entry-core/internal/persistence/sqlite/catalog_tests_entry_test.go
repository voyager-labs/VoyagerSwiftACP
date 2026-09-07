package sqlite

import "testing"

// The four entry test names below match the plan's documented verification
// command `go test -run '^(TestCatalogMapper|TestCatalogRepositoryLoad|TestCatalogDigest|TestCatalogSeedState)$'`.
// Each delegates to the concrete, descriptively-named suites so the documented
// command runs the full catalog mapper/repository/digest/seed-state coverage.

// TestCatalogMapper runs the explicit row<->domain mapper suites.
func TestCatalogMapper(t *testing.T) {
	t.Run("RejectsInvalidBLOB", TestCatalogMapperRejectsInvalidBLOB)
	t.Run("RejectsInvalidVersion", TestCatalogMapperRejectsInvalidVersion)
	t.Run("RejectsInvalidNaturalRefAndLifecycle", TestCatalogMapperRejectsInvalidNaturalRefAndLifecycle)
	t.Run("RejectsPartialSeedMetadata", TestCatalogMapperRejectsPartialSeedMetadata)
	t.Run("ValidRoundTrip", TestCatalogMapperValidRoundTrip)
}

// TestCatalogRepositoryLoad runs the single-load repository suites (no N+1,
// digest stability, corruption, orphan detection).
func TestCatalogRepositoryLoad(t *testing.T) {
	t.Run("1309", TestCatalogRepositoryLoad1309)
	t.Run("DigestEqualsFreshSeededReadBack", TestCatalogRepositoryDigestEqualsFreshSeededReadBack)
	t.Run("SameCountSubstitutionChangesDigest", TestCatalogRepositorySameCountSubstitutionChangesDigest)
	t.Run("MalformedIDFails", TestCatalogRepositoryMalformedIDFails)
	t.Run("OrphanRefFails", TestCatalogRepositoryOrphanRefFails)
}

// TestCatalogDigest runs the canonical-digest delegation suites.
func TestCatalogDigest(t *testing.T) {
	t.Run("UsesCanonicalImplementation", TestCatalogDigestUsesCanonicalImplementation)
	t.Run("IncludesStableFields", TestCatalogDigestIncludesStableFields)
}

// TestCatalogSeedState runs the seed-state derivation and corruption suites.
func TestCatalogSeedState(t *testing.T) {
	t.Run("Empty", TestCatalogSeedStateEmpty)
	t.Run("SingleTuple", TestCatalogSeedStateSingleTuple)
	t.Run("MixedTuplesIsCorruption", TestCatalogSeedStateMixedTuplesIsCorruption)
	t.Run("ZeroBindingsIsCorruption", TestCatalogSeedStateZeroBindingsIsCorruption)
}

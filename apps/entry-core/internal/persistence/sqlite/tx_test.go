package sqlite

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"gorm.io/gorm"
)

// assertFailure is a non-nil sentinel error the tx tests return to force a
// rollback (or, inside a nested call, a rollback to the savepoint only).
var assertFailure = errors.New("assert: force rollback")

// txRowCount returns the number of workspace_metadata rows, for asserting
// transaction commit/rollback visibility.
func txRowCount(t *testing.T, store *Store) int {
	t.Helper()
	var count int
	if err := store.SQLDB().QueryRowContext(context.Background(),
		"SELECT COUNT(*) FROM workspace_metadata").Scan(&count); err != nil {
		t.Fatalf("count rows: %v", err)
	}
	return count
}

// insertWorkspaceRow inserts a dummy workspace_metadata row (singleton = 1)
// inside the given tx, returning the tx's error.
func insertWorkspaceRow(tx *gorm.DB) error {
	return tx.Exec(
		`INSERT INTO workspace_metadata (singleton, workspace_id, created_at, updated_at)
		 VALUES (1, X'018F0000000000000000000000000000', datetime('now'), datetime('now'))`,
	).Error
}

func TestWithinTxCommitsOnNil(t *testing.T) {
	store := migratedStore(t)

	err := store.WithinTx(context.Background(), func(tx *gorm.DB) error {
		if err := insertWorkspaceRow(tx); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		t.Fatalf("WithinTx: %v", err)
	}

	if got := txRowCount(t, store); got != 1 {
		t.Fatalf("row count after committed tx = %d, want 1", got)
	}
}

func TestWithinTxRollbacksOnError(t *testing.T) {
	store := migratedStore(t)

	err := store.WithinTx(context.Background(), func(tx *gorm.DB) error {
		if err := insertWorkspaceRow(tx); err != nil {
			return err
		}
		return assertFailure // non-nil error -> rollback
	})
	if err == nil {
		t.Fatal("WithinTx returned nil, want the propagated error")
	}

	if got := txRowCount(t, store); got != 0 {
		t.Fatalf("row count after errored tx = %d, want 0 (rolled back)", got)
	}
}

func TestWithinTxRollbacksOnPanic(t *testing.T) {
	store := migratedStore(t)

	func() {
		defer func() {
			if r := recover(); r == nil {
				t.Fatal("expected fn panic to propagate")
			}
		}()
		_ = store.WithinTx(context.Background(), func(tx *gorm.DB) error {
			if err := insertWorkspaceRow(tx); err != nil {
				return err
			}
			panic("boom")
		})
	}()

	if got := txRowCount(t, store); got != 0 {
		t.Fatalf("row count after panicked tx = %d, want 0 (rolled back)", got)
	}
}

func TestWithinTxNestedSavepoint(t *testing.T) {
	store := migratedStore(t)

	err := store.WithinTx(context.Background(), func(outer *gorm.DB) error {
		if err := insertWorkspaceRow(outer); err != nil {
			return err
		}

		// Nested WithinTx uses GORM SAVEPOINT semantics: the inner tx may
		// roll back without rolling back the outer transaction. The enclosing
		// transaction is propagated to the nested call via WithTxScope.
		innerErr := store.WithinTx(store.WithTxScope(context.Background(), outer), func(inner *gorm.DB) error {
			if err := insertWorkspaceRow(inner); err != nil {
				return err
			}
			return assertFailure // inner rolls back to savepoint only
		})
		if innerErr == nil {
			t.Fatal("inner WithinTx returned nil, want error")
		}

		// Outer still commits: exactly one row.
		return nil
	})
	if err != nil {
		t.Fatalf("outer WithinTx: %v", err)
	}

	if got := txRowCount(t, store); got != 1 {
		t.Fatalf("row count after nested tx = %d, want 1 (inner rolled back only)", got)
	}
}

// TestWithinTxConcurrentIndependent proves two top-level WithinTx calls from
// different goroutines are serialized and independent: neither joins the
// other's transaction. workspace_metadata is singleton-constrained, so the
// probe uses a throwaway table. Goroutine 0 rolls back; goroutine 1 commits.
// Independence means goroutine 0's rollback must not take goroutine 1's
// committed row with it (which is exactly what happened under the old
// cross-goroutine SAVEPOINT-join bug).
func TestWithinTxConcurrentIndependent(t *testing.T) {
	store := migratedStore(t)

	if _, err := store.SQLDB().ExecContext(context.Background(),
		`CREATE TABLE concurrency_probe (id INTEGER PRIMARY KEY, marker TEXT)`); err != nil {
		t.Fatalf("create concurrency_probe: %v", err)
	}

	inTx0 := make(chan struct{})

	type result struct {
		err error
	}
	results := make([]result, 2)

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		results[0].err = store.WithinTx(context.Background(), func(tx *gorm.DB) error {
			if err := tx.Exec(
				`INSERT INTO concurrency_probe (marker) VALUES (?)`, "marker-0").Error; err != nil {
				return err
			}
			close(inTx0)
			// Keep the transaction open so goroutine 1's top-level call
			// overlaps it before we roll back.
			time.Sleep(50 * time.Millisecond)
			return assertFailure
		})
	}()

	go func() {
		defer wg.Done()
		<-inTx0
		results[1].err = store.WithinTx(context.Background(), func(tx *gorm.DB) error {
			return tx.Exec(
				`INSERT INTO concurrency_probe (marker) VALUES (?)`, "marker-1").Error
		})
	}()

	wg.Wait()

	if results[0].err == nil {
		t.Fatal("goroutine 0 WithinTx returned nil, want error (rollback)")
	}
	if results[1].err != nil {
		t.Fatalf("goroutine 1 WithinTx: %v", results[1].err)
	}

	for i, want := range []int{0, 1} {
		marker := fmt.Sprintf("marker-%d", i)
		var cnt int
		if err := store.SQLDB().QueryRowContext(context.Background(),
			`SELECT COUNT(*) FROM concurrency_probe WHERE marker = ?`, marker).Scan(&cnt); err != nil {
			t.Fatalf("query %s: %v", marker, err)
		}
		if cnt != want {
			t.Fatalf("%s count = %d, want %d (independent top-level tx)", marker, cnt, want)
		}
	}
}

// TestWithinTxChildGoroutineJoinsSavepoint is a regression test for the P1
// deadlock where a WithinTx callback spawns a child goroutine that calls
// WithinTx again (a logically-nested operation) while the parent waits for it.
// The old goroutine-ID based re-entrancy detection gave the child a different
// GID, so it took the "independent" path and blocked on txMu.Lock() while the
// parent already held txMu and waited for the child -> deadlock.
//
// With the WithTxScope design, the parent propagates the tx-scoped *gorm.DB to
// the child via the context, so the child joins the enclosing transaction as a
// GORM SAVEPOINT regardless of goroutine. The child's rollback must be
// independent of the parent: after the outer commits, marker-outer exists and
// marker-child is absent (the inner rolled back to the SAVEPOINT only).
func TestWithinTxChildGoroutineJoinsSavepoint(t *testing.T) {
	store := migratedStore(t)

	if _, err := store.SQLDB().ExecContext(context.Background(),
		`CREATE TABLE child_scope_probe (id INTEGER PRIMARY KEY, marker TEXT)`); err != nil {
		t.Fatalf("create child_scope_probe: %v", err)
	}

	outerErr := store.WithinTx(context.Background(), func(outer *gorm.DB) error {
		if err := outer.Exec(
			`INSERT INTO child_scope_probe (marker) VALUES (?)`, "marker-outer").Error; err != nil {
			return err
		}

		// Propagate the enclosing transaction to a child goroutine via the
		// context. The child joins the outer transaction as a SAVEPOINT
		// instead of blocking on txMu (which the parent already holds).
		childCtx := store.WithTxScope(context.Background(), outer)

		done := make(chan error, 1)
		go func() {
			done <- store.WithinTx(childCtx, func(inner *gorm.DB) error {
				if err := inner.Exec(
					`INSERT INTO child_scope_probe (marker) VALUES (?)`, "marker-child").Error; err != nil {
					return err
				}
				return assertFailure // child rolls back to SAVEPOINT only
			})
		}()

		// Parent waits for the child. On the OLD goroutine-ID code this
		// deadlocks: the child blocks on txMu while the parent holds it and
		// waits for the child. Use a bounded wait so a hang becomes a clean
		// test failure rather than an infinite hang.
		select {
		case childErr := <-done:
			if childErr == nil {
				t.Fatal("child WithinTx returned nil, want the propagated error")
			}
		case <-time.After(5 * time.Second):
			t.Fatal("deadlock: child WithinTx did not complete")
		}

		// Outer still commits: marker-outer persists, marker-child does not.
		return nil
	})
	if outerErr != nil {
		t.Fatalf("outer WithinTx: %v", outerErr)
	}

	var outerCnt int
	if err := store.SQLDB().QueryRowContext(context.Background(),
		`SELECT COUNT(*) FROM child_scope_probe WHERE marker = ?`, "marker-outer").Scan(&outerCnt); err != nil {
		t.Fatalf("query marker-outer: %v", err)
	}
	if outerCnt != 1 {
		t.Fatalf("marker-outer count = %d, want 1 (outer committed)", outerCnt)
	}

	var childCnt int
	if err := store.SQLDB().QueryRowContext(context.Background(),
		`SELECT COUNT(*) FROM child_scope_probe WHERE marker = ?`, "marker-child").Scan(&childCnt); err != nil {
		t.Fatalf("query marker-child: %v", err)
	}
	if childCnt != 0 {
		t.Fatalf("marker-child count = %d, want 0 (child rolled back to SAVEPOINT only)", childCnt)
	}
}

// TestWithinTxNestedHonorsCanceledContext proves a nested WithinTx applies the
// caller's ctx even though the surrounding top-level transaction was opened
// with context.Background(). The inner callback issues an INSERT with the
// already-canceled context and must fail with a context error; under the old
// code the inner path ran on the outer (Background) context, so the insert
// would succeed and this test would fail.
// TestWithinTxConcurrentChildrenSameScopeNoErase is a regression test for the
// P1 correctness bug where concurrent children sharing the SAME WithTxScope
// created independent GORM SAVEPOINTs on the same *sql.Tx. SQLite's
// ROLLBACK TO <earlier-savepoint> discards all later savepoints AND their
// writes, so one child's rollback silently erased another child's committed
// write. The per-scope mutex serializes nested executions on one scope so a
// child's rollback can never discard a sibling's committed savepoint.
//
// Child 1 opens its savepoint, inserts sibling-a, then signals child 2 to run
// and waits (bounded, non-fatal) for child 2 to finish before rolling back.
// Under the OLD (no-mutex) code child 2 commits sibling-b inside child 1's
// savepoint scope while child 1 is still open, and child 1's ROLLBACK TO sp1
// discards it. Under the NEW (per-scope mutex) code child 2 blocks on the
// mutex until child 1's savepoint is fully released, so its committed
// sibling-b write survives the outer commit.
func TestWithinTxConcurrentChildrenSameScopeNoErase(t *testing.T) {
	store := migratedStore(t)

	if _, err := store.SQLDB().ExecContext(context.Background(),
		`CREATE TABLE scope_sibling_probe (id INTEGER PRIMARY KEY, marker TEXT)`); err != nil {
		t.Fatalf("create scope_sibling_probe: %v", err)
	}

	outerErr := store.WithinTx(context.Background(), func(outer *gorm.DB) error {
		// Both children share this single scope: they run their nested
		// SAVEPOINT executions on the SAME *sql.Tx.
		childCtx := store.WithTxScope(context.Background(), outer)

		type result struct{ err error }
		results := make([]result, 2)
		child2Start := make(chan struct{})
		child2Done := make(chan struct{})

		var wg sync.WaitGroup
		wg.Add(2)

		go func() {
			defer wg.Done()
			results[0].err = store.WithinTx(childCtx, func(inner *gorm.DB) error {
				if err := inner.Exec(
					`INSERT INTO scope_sibling_probe (marker) VALUES (?)`, "sibling-a").Error; err != nil {
					return err
				}
				// Signal child 2 to run, then wait a bounded window for it to
				// commit before rolling back. Old code lets child 2 interleave
				// and commit inside this savepoint scope; the mutex prevents
				// that, so child 2 only commits after this savepoint is
				// released and sibling-b survives.
				close(child2Start)
				select {
				case <-child2Done:
				case <-time.After(200 * time.Millisecond):
				}
				return assertFailure // child 1 rolls back its savepoint only
			})
		}()

		go func() {
			defer wg.Done()
			<-child2Start
			results[1].err = store.WithinTx(childCtx, func(inner *gorm.DB) error {
				if err := inner.Exec(
					`INSERT INTO scope_sibling_probe (marker) VALUES (?)`, "sibling-b").Error; err != nil {
					return err
				}
				return nil // child 2 commits its savepoint
			})
			close(child2Done)
		}()

		// Bounded wait so a hang (e.g. a regression to a deadlock) becomes a
		// clean failure rather than an infinite hang.
		done := make(chan struct{})
		go func() { wg.Wait(); close(done) }()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Fatal("timed out waiting for sibling children")
		}

		if results[0].err == nil {
			t.Fatal("child 1 WithinTx returned nil, want the propagated error")
		}
		if results[1].err != nil {
			t.Fatalf("child 2 WithinTx: %v", results[1].err)
		}

		return nil // outer tx commits
	})
	if outerErr != nil {
		t.Fatalf("outer WithinTx: %v", outerErr)
	}

	for _, tc := range []struct {
		marker string
		want   int
	}{
		{"sibling-a", 0}, // child 1 rolled back its savepoint only
		{"sibling-b", 1}, // child 2's committed write must survive the outer commit
	} {
		var cnt int
		if err := store.SQLDB().QueryRowContext(context.Background(),
			`SELECT COUNT(*) FROM scope_sibling_probe WHERE marker = ?`, tc.marker).Scan(&cnt); err != nil {
			t.Fatalf("query %s: %v", tc.marker, err)
		}
		if cnt != tc.want {
			t.Fatalf("%s count = %d, want %d", tc.marker, cnt, tc.want)
		}
	}
}

func TestWithinTxNestedHonorsCanceledContext(t *testing.T) {
	store := migratedStore(t)

	outerErr := store.WithinTx(context.Background(), func(outer *gorm.DB) error {
		// workspace_metadata is singleton-constrained, so use a throwaway table
		// (same pattern as TestWithinTxConcurrentIndependent) to probe whether
		// the inner canceled context is honored.
		if err := outer.Exec(`CREATE TABLE ctx_probe (id INTEGER PRIMARY KEY, marker TEXT)`).Error; err != nil {
			return err
		}

		innerCtx, cancel := context.WithCancel(store.WithTxScope(context.Background(), outer))
		cancel() // already canceled before the nested call

		innerErr := store.WithinTx(innerCtx, func(inner *gorm.DB) error {
			return inner.Exec(`INSERT INTO ctx_probe (marker) VALUES (?)`, "ctx-marker").Error
		})
		if innerErr == nil {
			t.Fatal("nested WithinTx with canceled ctx returned nil, want a context error")
		}
		return nil
	})
	if outerErr != nil {
		t.Fatalf("outer WithinTx: %v", outerErr)
	}
}

// TestWithinTxMultiLevelNestedDerivedScopes proves multi-level nesting works
// when each level derives a FRESH scope (via WithTxScope on the current level's
// tx). Each nesting level gets its own non-reentrant scope gate, so nesting
// proceeds as a stack of SAVEPOINTs without deadlock. The deepest level rolls
// back only its own SAVEPOINT; the outer and middle levels must commit.
func TestWithinTxMultiLevelNestedDerivedScopes(t *testing.T) {
	store := migratedStore(t)

	if _, err := store.SQLDB().ExecContext(context.Background(),
		`CREATE TABLE multilevel_probe (id INTEGER PRIMARY KEY, marker TEXT)`); err != nil {
		t.Fatalf("create multilevel_probe: %v", err)
	}

	done := make(chan error, 1)
	var level2Err error
	go func() {
		done <- store.WithinTx(context.Background(), func(tx *gorm.DB) error {
			if err := tx.Exec(
				`INSERT INTO multilevel_probe (marker) VALUES (?)`, "level-0").Error; err != nil {
				return err
			}

			// Level 1 derives a FRESH scope from the outer tx.
			return store.WithinTx(store.WithTxScope(context.Background(), tx), func(level1 *gorm.DB) error {
				if err := level1.Exec(
					`INSERT INTO multilevel_probe (marker) VALUES (?)`, "level-1").Error; err != nil {
					return err
				}

				// Level 2 derives ANOTHER fresh scope from level 1's tx. It
				// does NOT reuse level 1's scope: reuse is a contract
				// violation that fails fast (see TestWithinTxSameScopeReuseFailsFast).
				level2Err = store.WithinTx(store.WithTxScope(context.Background(), level1), func(level2 *gorm.DB) error {
					if err := level2.Exec(
						`INSERT INTO multilevel_probe (marker) VALUES (?)`, "level-2").Error; err != nil {
						return err
					}
					return assertFailure // deepest SAVEPOINT rolls back only
				})
				return nil
			})
		})
	}()

	// Bounded wait so a deadlock becomes a clean failure instead of a hang.
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("outer WithinTx: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("deadlock: multi-level nested WithinTx with derived scopes did not complete")
	}

	if level2Err == nil {
		t.Fatal("level-2 WithinTx returned nil, want the propagated error")
	}

	for _, tc := range []struct {
		marker string
		want   int
	}{
		{"level-0", 1}, // outer committed
		{"level-1", 1}, // level-1 committed (only the deepest rolled back)
		{"level-2", 0}, // deepest SAVEPOINT rolled back only
	} {
		var cnt int
		if err := store.SQLDB().QueryRowContext(context.Background(),
			`SELECT COUNT(*) FROM multilevel_probe WHERE marker = ?`, tc.marker).Scan(&cnt); err != nil {
			t.Fatalf("query %s: %v", tc.marker, err)
		}
		if cnt != tc.want {
			t.Fatalf("%s count = %d, want %d", tc.marker, cnt, tc.want)
		}
	}
}

// TestWithinTxSameScopeReuseFailsFast proves that re-using the SAME scope for a
// nested WithinTx fails fast with a descriptive error instead of deadlocking
// (or silently re-entering). Because the scope gate is NON-reentrant and
// legitimate nesting always derives a fresh scope, a same-goroutine re-entry of
// an already-held scope is a contract violation: lock() detects it via the
// heldGID fail-fast guard and returns an error immediately. Under the OLD
// GID-keyed reentrant lock this call would have re-entered silently (no error);
// under a plain non-reentrant mutex it would have deadlocked. Here it must fail
// fast within a bounded time.
func TestWithinTxSameScopeReuseFailsFast(t *testing.T) {
	store := migratedStore(t)

	done := make(chan error, 1)
	var level2Err error
	go func() {
		done <- store.WithinTx(context.Background(), func(tx *gorm.DB) error {
			// One scope shared by both levels: the deeper call re-uses it.
			scopeCtx := store.WithTxScope(context.Background(), tx)
			_ = store.WithinTx(scopeCtx, func(level1 *gorm.DB) error {
				// Deeper nested call REUSING the same scope on the same
				// goroutine: must fail fast with a descriptive error, not hang
				// and not re-enter.
				level2Err = store.WithinTx(scopeCtx, func(level2 *gorm.DB) error {
					return nil
				})
				return nil
			})
			return nil
		})
	}()

	// Bounded wait so a hang (regression to deadlock) becomes a clean failure.
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("outer WithinTx: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("same-scope reuse did not fail fast; it hung (deadlock)")
	}

	if level2Err == nil {
		t.Fatal("same-scope reuse WithinTx returned nil, want a descriptive fail-fast error")
	}
	if !strings.Contains(level2Err.Error(), "derive a fresh scope") {
		t.Fatalf("same-scope reuse error = %q, want a descriptive 'derive a fresh scope' error", level2Err)
	}
}

// TestTxScopeHandoffPreservesNewOwnerGID is a regression test for the P1 race
// where unlock() released the gate mu BEFORE clearing heldGID. A sibling that
// acquired mu right after mu.Unlock() and recorded its own heldGID in lock()
// could have that value clobbered to 0 by the previous owner's heldGID = 0. If
// that sibling then reused the scope on the same goroutine, the fail-fast
// detector saw heldGID == 0 (wrongly "free") and self-deadlocked on mu.Lock()
// instead of failing fast. The fix clears heldGID BEFORE releasing mu, so the
// next owner's lock() always records its own GID without being overwritten.
func TestTxScopeHandoffPreservesNewOwnerGID(t *testing.T) {
	scope := &txScope{tx: &gorm.DB{}, gate: &txGate{}}

	// Owner A (main goroutine) acquires, then fully releases.
	if err := scope.gate.lock(); err != nil {
		t.Fatalf("A lock: %v", err)
	}
	scope.gate.unlock()

	// Owner B acquires the now-free gate on a dedicated goroutine (so A and B
	// differ), then reuses it on the SAME goroutine that holds it. Runs in a
	// single goroutine so B's reuse is genuinely same-goroutine re-entry, which
	// the fail-fast detector must catch rather than self-deadlocking.
	done := make(chan error, 1)
	go func() {
		if err := scope.gate.lock(); err != nil {
			done <- fmt.Errorf("B lock: %v", err)
			return
		}
		// B's heldGID must be recorded, not clobbered to 0 by A's release.
		scope.gate.stateMu.Lock()
		gid := scope.gate.heldGID
		scope.gate.stateMu.Unlock()
		if gid == 0 {
			done <- fmt.Errorf("B's heldGID was clobbered to 0 by the previous owner's release; fail-fast detector would be wrong and B would self-deadlock on reuse")
			return
		}
		reuseErr := scope.gate.lock() // same goroutine as B's acquire -> must fail fast
		if reuseErr == nil {
			done <- fmt.Errorf("B's scope reuse returned nil, want a fail-fast error")
			return
		}
		if !strings.Contains(reuseErr.Error(), "derive a fresh scope") {
			done <- fmt.Errorf("B's scope reuse error = %q, want a descriptive 'derive a fresh scope' error", reuseErr)
			return
		}
		scope.gate.unlock()
		done <- nil
	}()

	// Bounded wait so a regression to deadlock becomes a clean failure.
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("B's scope reuse deadlocked instead of failing fast (heldGID clobbered by previous owner)")
	}
}

// TestWithinTxSiblingsOwnScopesNoErase is the regression test for the P1 bug
// where two sibling children inside ONE outer transaction each derive their OWN
// fresh scope (two separate WithTxScope calls on the SAME outer *gorm.DB). Under
// the OLD per-scope-mutex design each sibling's scope got its OWN mutex, so
// there was no serialization: they opened GORM SAVEPOINTs on the same *sql.Tx
// concurrently, and one sibling's ROLLBACK TO discarded the other's committed
// savepoint write.
//
// Under the NEW shared-gate-per-*gorm.DB design, both siblings derive scopes
// that reference the SAME gate (keyed by the outer *gorm.DB), so their nested
// SAVEPOINT executions serialize: child B commits sibling-b only after child
// A's savepoint is fully released, so child A's rollback can never erase it.
//
// Child A inserts sibling-a then rolls back (assertFailure); child B inserts
// sibling-b then commits. The parent waits for both (bounded) and, after the
// outer commits, asserts sibling-a is absent (rolled back) and sibling-b is
// present (must survive child A's rollback). On the OLD code sibling-b would be
// erased (count 0) — the P1.
func TestWithinTxSiblingsOwnScopesNoErase(t *testing.T) {
	store := migratedStore(t)

	if _, err := store.SQLDB().ExecContext(context.Background(),
		`CREATE TABLE sibling_own_scope_probe (id INTEGER PRIMARY KEY, marker TEXT)`); err != nil {
		t.Fatalf("create sibling_own_scope_probe: %v", err)
	}

	outerErr := store.WithinTx(context.Background(), func(outer *gorm.DB) error {
		// TWO SEPARATE WithTxScope calls on the SAME outer *gorm.DB: each child
		// derives its OWN fresh scope. The P1 arises precisely because the two
		// scopes are distinct values, so the old per-scope mutex gave them
		// different gates. The shared gate keyed by outer must serialize them.
		childACtx := store.WithTxScope(context.Background(), outer)
		childBCtx := store.WithTxScope(context.Background(), outer)

		type result struct{ err error }
		results := make([]result, 2)

		childBStart := make(chan struct{})
		childBDone := make(chan struct{})

		var wg sync.WaitGroup
		wg.Add(2)

		go func() {
			defer wg.Done()
			results[0].err = store.WithinTx(childACtx, func(inner *gorm.DB) error {
				if err := inner.Exec(
					`INSERT INTO sibling_own_scope_probe (marker) VALUES (?)`, "sibling-a").Error; err != nil {
					return err
				}
				// Signal child B to run, then wait a bounded window for it to
				// commit before rolling back. On the OLD per-scope-mutex code
				// child B interleaves (different mutex) and commits sibling-b
				// inside child A's still-open savepoint scope; child A's
				// ROLLBACK TO then discards it. The shared gate prevents that.
				close(childBStart)
				select {
				case <-childBDone:
				case <-time.After(200 * time.Millisecond):
				}
				return assertFailure // child A rolls back its savepoint only
			})
		}()

		go func() {
			defer wg.Done()
			<-childBStart
			results[1].err = store.WithinTx(childBCtx, func(inner *gorm.DB) error {
				if err := inner.Exec(
					`INSERT INTO sibling_own_scope_probe (marker) VALUES (?)`, "sibling-b").Error; err != nil {
					return err
				}
				return nil // child B commits its savepoint
			})
			close(childBDone)
		}()

		// Bounded wait so a regression to deadlock becomes a clean failure
		// rather than an infinite hang.
		done := make(chan struct{})
		go func() { wg.Wait(); close(done) }()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Fatal("timed out waiting for sibling children")
		}

		if results[0].err == nil {
			t.Fatal("child A WithinTx returned nil, want the propagated error")
		}
		if results[1].err != nil {
			t.Fatalf("child B WithinTx: %v", results[1].err)
		}

		return nil // outer tx commits
	})
	if outerErr != nil {
		t.Fatalf("outer WithinTx: %v", outerErr)
	}

	for _, tc := range []struct {
		marker string
		want   int
	}{
		{"sibling-a", 0}, // child A rolled back its savepoint only
		{"sibling-b", 1}, // child B's committed write must survive child A's rollback (the P1)
	} {
		var cnt int
		if err := store.SQLDB().QueryRowContext(context.Background(),
			`SELECT COUNT(*) FROM sibling_own_scope_probe WHERE marker = ?`, tc.marker).Scan(&cnt); err != nil {
			t.Fatalf("query %s: %v", tc.marker, err)
		}
		if cnt != tc.want {
			t.Fatalf("%s count = %d, want %d", tc.marker, cnt, tc.want)
		}
	}
}

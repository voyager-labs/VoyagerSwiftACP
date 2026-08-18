package sqlite

import (
	"context"
	"fmt"
	"runtime"
	"strings"
	"sync"

	"gorm.io/gorm"
)

// txState serializes top-level transactions on the store's single connection.
// txMu is held for the entire top-level transaction, so only one independent
// *sql.Tx exists on the single connection at a time; an independent top-level
// call from any goroutine waits for the current one to finish and then begins
// its own fresh transaction.
type txState struct {
	txMu sync.Mutex // held for the entire top-level transaction
}

// txScopeKey is the context key carrying an in-flight transaction binding.
type txScopeKey struct{}

// txGate serializes nested SAVEPOINT executions that share the same tx-scoped
// *gorm.DB session. All scopes derived from the SAME *gorm.DB share one gate;
// distinct *gorm.DB values (different nesting levels) get distinct gates, so
// multi-level nesting is preserved (a gate never falsely fails fast across
// nesting levels, because each level uses a different *gorm.DB and therefore a
// different gate).
//
// The gate (mu) is NON-reentrant: concurrent different-goroutine siblings that
// share the gate serialize by blocking on mu.Lock() until the holder fully
// releases it. This is what keeps sibling SAVEPOINT executions from
// interleaving on the same *sql.Tx (each child's rollback can never discard a
// sibling's committed savepoint).
//
// Re-using a scope for a NESTED WithinTx on the SAME goroutine is a contract
// violation: legitimate nesting always derives a FRESH scope per level via
// WithTxScope. Because the gate is non-reentrant, that reuse would otherwise
// self-deadlock, so a lightweight fail-fast detector (stateMu + heldGID)
// returns a descriptive error instead of hanging. The detector only fires for
// same-goroutine re-entry; a different-goroutine sibling still blocks on mu and
// serializes, so sibling behavior is unweakened.
type txGate struct {
	mu sync.Mutex // shared gate; siblings sharing the same *gorm.DB serialize here (non-reentrant)

	// stateMu guards heldGID. heldGID is used ONLY by the fail-fast detector to
	// catch same-goroutine re-entry of an already-held gate; it never grants
	// reentrancy (a held gate can never be acquired again on any goroutine
	// without first being released).
	stateMu sync.Mutex
	heldGID uint64 // goroutine currently holding the gate (0 = free)
}

// lock acquires the gate for the calling goroutine, blocking to serialize with
// different-goroutine siblings. It returns a descriptive error instead of
// blocking when the SAME goroutine re-enters a gate it already holds (a
// contract violation — nested nesting must derive a fresh scope), so the
// non-reentrant gate can never self-deadlock.
func (g *txGate) lock() error {
	gid := goid()

	g.stateMu.Lock()
	if g.heldGID != 0 && g.heldGID == gid {
		// Same-goroutine re-entry of a gate we already hold: fail fast rather
		// than self-deadlocking on the non-reentrant gate. This is a contract
		// violation — each nesting level must derive a fresh scope.
		g.stateMu.Unlock()
		return fmt.Errorf("transaction scope reused for a nested WithinTx on the same goroutine; derive a fresh scope with WithTxScope per nesting level")
	}
	g.stateMu.Unlock()

	// Acquire the non-reentrant gate. A free gate locks immediately; a
	// different-goroutine sibling (or cross-goroutine reuse, which the contract
	// forbids) blocks here and serializes until the holder releases (Comment 13
	// preserved).
	g.mu.Lock()
	g.stateMu.Lock()
	g.heldGID = gid
	g.stateMu.Unlock()
	return nil
}

// unlock releases the gate, waking the next blocked sibling. It must only be
// called after a successful lock (matched via defer).
//
// Ordering is load-bearing: heldGID is cleared (under stateMu) BEFORE mu is
// released. Releasing mu first would let a waiting sibling record its own
// heldGID in lock(), only for the previous owner's heldGID = 0 to clobber it —
// the sibling then sees the gate it holds as free, the fail-fast detector does
// not fire, and it self-deadlocks on mu.Lock(). Clearing heldGID first keeps
// the fail-fast detector correct across owner handoff.
func (g *txGate) unlock() {
	g.stateMu.Lock()
	g.heldGID = 0
	g.stateMu.Unlock()
	g.mu.Unlock()
}

// txScope binds a tx-scoped *gorm.DB (whose Statement.ConnPool is the active
// *sql.Tx) to a context. It is stored as a *txScope pointer in the context
// value so the binding is SHARED across every retrieval of the same scope (a
// value sync.Mutex would be copied, which is a go vet/race error).
//
// The scope does NOT own serialization state; it references a txGate shared by
// every scope derived from the same tx-scoped *gorm.DB. This is what fixes the
// P1 sibling bug: two sibling children that each independently call
// WithTxScope on the SAME outer *gorm.DB must serialize on ONE gate, even
// though they hold distinct scope values (each with a fresh pointer).
type txScope struct {
	tx   *gorm.DB
	gate *txGate // shared across all scopes derived from the same *gorm.DB
}

// txGateRegistry maps a tx-scoped *gorm.DB (the exact value passed to
// WithTxScope) to its serialization gate. Sibling scopes derived from the SAME
// *gorm.DB share a gate; scopes at different nesting levels (different
// *gorm.DB values) get distinct gates, so multi-level nesting is preserved.
type txGateRegistry struct {
	mu    sync.Mutex
	gates map[*gorm.DB]*txGate
}

// gateFor returns the gate for the given tx-scoped *gorm.DB, creating one on
// first use. The returned gate is shared by every scope derived from that same
// *gorm.DB.
func (r *txGateRegistry) gateFor(tx *gorm.DB) *txGate {
	r.mu.Lock()
	defer r.mu.Unlock()
	if g, ok := r.gates[tx]; ok {
		return g
	}
	g := &txGate{}
	r.gates[tx] = g
	return g
}

// purgeRootConnPool removes every gate whose tx-scoped *gorm.DB still points at
// the given root *sql.Tx connection pool. It is called when a top-level
// transaction ends so a stale gate can never be reused for a subsequent
// transaction on a recycled *gorm.DB value.
//
// Coupling note: this relies on gorm v1.31.2 preserving Statement.ConnPool (the
// raw *sql.Tx) at EVERY nesting level — a nested Transaction uses a SAVEPOINT on
// the same ConnPool and Session clones preserve ConnPool. If a future gorm
// version wraps the nested ConnPool in a distinct type, the equality here would
// need unwrapping to compare against the root.
func (r *txGateRegistry) purgeRootConnPool(root interface{}) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for gdb := range r.gates {
		if gdb.Statement.ConnPool == root {
			delete(r.gates, gdb)
		}
	}
}

// goid returns the calling goroutine's ID, parsed from runtime.Stack. It is
// used ONLY by the fail-fast detector to distinguish same-goroutine scope
// re-entry (a contract violation) from a different-goroutine sibling (which
// must serialize); it is never used for the top-level-vs-nested decision, which
// remains purely scope-based, and never grants reentrancy.
func goid() uint64 {
	var buf [64]byte
	n := runtime.Stack(buf[:], false)
	// runtime.Stack writes "goroutine N [<state>]:" first.
	s := string(buf[:n])
	s = s[len("goroutine"):]
	s = strings.TrimLeft(s, " \t")
	var gid uint64
	for _, c := range s {
		if c < '0' || c > '9' {
			break
		}
		gid = gid*10 + uint64(c-'0')
	}
	return gid
}

// WithTxScope binds a tx-scoped *gorm.DB to ctx. A WithinTx call made with a
// context derived from this joins the enclosing transaction as a GORM
// SAVEPOINT, regardless of goroutine. Pass ctx (or a derived child context)
// to any child goroutine that must mutate inside the enclosing transaction.
//
// Nested (SAVEPOINT) executions that share the same *gorm.DB (even via
// INDEPENDENT scopes derived from that same tx) are serialized by ONE shared
// gate, so concurrent siblings cannot interleave their SAVEPOINTs on the same
// *sql.Tx and corrupt each other's writes — regardless of whether they reuse a
// single scope or each derive their own fresh scope from the same outer tx.
// Distinct *gorm.DB values (different nesting levels) get distinct gates, and
// independent top-level calls are unaffected.
//
// CONTRACT: each nesting level MUST derive a FRESH scope by calling
// WithTxScope on the current level's tx; re-using a scope for a deeper nested
// WithinTx is a contract violation and fails fast with a descriptive error.
func (store *Store) WithTxScope(ctx context.Context, tx *gorm.DB) context.Context {
	gate := store.gates.gateFor(tx)
	return context.WithValue(ctx, txScopeKey{}, &txScope{tx: tx, gate: gate})
}

// WithinTx executes fn inside a single serialized write transaction on the
// shared connection. It commits when fn returns nil and rolls back when fn
// returns an error or panics (the panic is re-raised after rollback).
//
// Logical nesting is expressed by propagating a WithTxScope context to the
// nested call: a WithinTx call made with a context carrying a tx scope joins
// the enclosing transaction with GORM SAVEPOINT semantics (the inner rollback
// reverts only the inner changes), regardless of which goroutine makes the
// call. Pass the WithTxScope-derived context (or a child of it) to any child
// goroutine that must mutate inside the enclosing transaction.
//
// Any scope-less call is an independent top-level transaction: it is
// serialized on the single connection by txMu and does not join any
// surrounding transaction, even if one is running on another goroutine. This
// is the single mutation boundary VOY-765 repositories are allowed to use;
// they receive the tx-scoped *gorm.DB and own their table mapping.
func (store *Store) WithinTx(ctx context.Context, fn func(tx *gorm.DB) error) error {
	if scope, ok := ctx.Value(txScopeKey{}).(*txScope); ok && scope != nil && scope.tx != nil {
		if err := scope.gate.lock(); err != nil {
			return err
		}
		defer scope.gate.unlock()
		return scope.tx.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			return fn(tx)
		})
	}

	store.txState.txMu.Lock()
	defer store.txState.txMu.Unlock()

	return store.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Purge all gates belonging to this top-level transaction once it ends.
		// tx.Statement.ConnPool is the fresh *sql.Tx for this top-level tx.
		defer store.gates.purgeRootConnPool(tx.Statement.ConnPool)
		return fn(tx)
	})
}

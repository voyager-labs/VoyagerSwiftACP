package sqlite

import (
	"context"
	"sync"

	"gorm.io/gorm"
)

// txState tracks the transaction active on the store's single connection so a
// re-entrant WithinTx call (from inside a callback) runs as a GORM SAVEPOINT
// instead of beginning a fresh transaction that would deadlock on the one
// available connection.
type txState struct {
	mu       sync.Mutex
	activeTx *gorm.DB
}

// WithinTx executes fn inside a single serialized write transaction on the
// shared connection. It commits when fn returns nil and rolls back when fn
// returns an error or panics (the panic is re-raised after rollback). A nested
// WithinTx call from inside fn runs on the surrounding transaction with GORM
// SAVEPOINT semantics, so the inner rollback reverts only the inner changes.
// This is the single mutation boundary VOY-765 repositories are allowed to use;
// they receive the tx-scoped *gorm.DB and own their table mapping.
func (store *Store) WithinTx(ctx context.Context, fn func(tx *gorm.DB) error) error {
	if active := store.currentTx(); active != nil {
		// Re-entrant call: GORM's Transaction on a tx-scoped *gorm.DB detects
		// the surrounding *sql.Tx and uses a SAVEPOINT, rolling back to it on
		// error.
		return active.Transaction(func(tx *gorm.DB) error {
			return fn(tx)
		})
	}

	return store.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		store.setActiveTx(tx)
		defer store.clearActiveTx()
		return fn(tx)
	})
}

func (store *Store) currentTx() *gorm.DB {
	store.txState.mu.Lock()
	defer store.txState.mu.Unlock()
	return store.txState.activeTx
}

func (store *Store) setActiveTx(tx *gorm.DB) {
	store.txState.mu.Lock()
	store.txState.activeTx = tx
	store.txState.mu.Unlock()
}

func (store *Store) clearActiveTx() {
	store.txState.mu.Lock()
	store.txState.activeTx = nil
	store.txState.mu.Unlock()
}

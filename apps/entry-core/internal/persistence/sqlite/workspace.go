package sqlite

import (
	"context"
	"errors"

	"gorm.io/gorm"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// ErrWorkspaceCorrupt is returned when the persisted workspace identity blob is
// present but not a valid UUIDv7 (wrong length or wrong version/variant bits).
// The store fails closed: it never auto-repairs and never derives identity from
// path, environment, or account.
var ErrWorkspaceCorrupt = errors.New("workspace identity corrupt")

// BootstrapOrRestoreWorkspace returns the DB-owned workspace identity,
// creating it on first run and restoring the persisted identity on subsequent
// runs. Both paths run inside a single WithinTx. The identity is owned by the
// database: it is never derived from path, environment, or account (ADR-012).
func (store *Store) BootstrapOrRestoreWorkspace(ctx context.Context) (domainentry.WorkspaceContext, error) {
	var wsctx domainentry.WorkspaceContext

	err := store.WithinTx(ctx, func(tx *gorm.DB) error {
		var row WorkspaceMetadataRow
		err := tx.Where("singleton = 1").First(&row).Error
		switch {
		case errors.Is(err, gorm.ErrRecordNotFound):
			// Absent row -> generate a fresh identity and persist it.
			id, err := domainentry.NewWorkspaceID()
			if err != nil {
				return err
			}
			if err := tx.Create(&WorkspaceMetadataRow{
				Singleton:   1,
				WorkspaceID: id.Bytes(),
			}).Error; err != nil {
				return err
			}
			wsctx.ID = id
			return nil
		case err != nil:
			return err
		}

		// Row present -> restore; a corrupt blob fails closed.
		id, err := domainentry.ParseWorkspaceID(row.WorkspaceID)
		if err != nil {
			return ErrWorkspaceCorrupt
		}
		wsctx.ID = id
		return nil
	})
	if err != nil {
		return domainentry.WorkspaceContext{}, err
	}
	return wsctx, nil
}

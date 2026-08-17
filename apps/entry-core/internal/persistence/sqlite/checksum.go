package sqlite

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strings"
)

// ErrMigrationChecksum is returned when the embedded migration directory fails
// integrity verification against atlas.sum (tampered, unlisted, or missing
// .up.sql files, or an orphaned .down.sql). The daemon maps it to exit 1.
var ErrMigrationChecksum = errors.New("migration checksum failed")

// fileHash returns the Atlas per-file hash for a migration file:
// base64(sha256(name + content)). This is exactly what atlas.sum stores for
// each *.up.sql entry; the algorithm is confirmed against the pinned CLI's
// generated atlas.sum (the test oracle).
func fileHash(name string, content []byte) string {
	h := sha256.New()
	h.Write([]byte(name))
	h.Write(content)
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// sumHash returns the atlas.sum overall hash:
// base64(sha256 over each entry's (name + per-file-hash)) in atlas.sum order.
func sumHash(entries []sumEntry) string {
	h := sha256.New()
	for _, e := range entries {
		h.Write([]byte(e.name))
		h.Write([]byte(e.hash))
	}
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

type sumEntry struct {
	name string
	hash string
}

// parseSum parses an atlas.sum file: the first line is the overall hash
// (h1:<sum>) and each subsequent line is "<name> h1:<per-file-hash>". It
// returns the parsed entries and the declared overall hash.
func parseSum(data []byte) ([]sumEntry, string, error) {
	sc := bufio.NewScanner(bytes.NewReader(data))
	if !sc.Scan() {
		return nil, "", fmt.Errorf("%w: empty atlas.sum", ErrMigrationChecksum)
	}
	declaredSum := strings.TrimPrefix(sc.Text(), "h1:")
	var entries []sumEntry
	for sc.Scan() {
		line := sc.Text()
		parts := strings.SplitN(line, " h1:", 2)
		if len(parts) != 2 {
			return nil, "", fmt.Errorf("%w: malformed entry %q", ErrMigrationChecksum, line)
		}
		entries = append(entries, sumEntry{name: parts[0], hash: parts[1]})
	}
	if err := sc.Err(); err != nil {
		return nil, "", fmt.Errorf("%w: %v", ErrMigrationChecksum, err)
	}
	return entries, declaredSum, nil
}

// VerifyEmbeddedMigrations verifies the migration directory against atlas.sum,
// scoped to exactly the Atlas golang-migrate dir format:
//
//   - *.up.sql files are the only files Atlas hashes; each is checked for a
//     listed atlas.sum entry whose per-file hash matches the file content.
//   - every atlas.sum entry must name a *.up.sql that exists in the directory.
//   - *.down.sql files are never hash-verified; they are checked only for
//     existence and for a paired *.up.sql by name (an orphan .down.sql fails).
//
// The atlas.sum overall hash is verified so a tampered sum file itself is
// rejected. Any violation fails closed with ErrMigrationChecksum.
//
// fsys is expected to contain a `migrations` subdirectory (the embedded
// directory), matching how MigrateUp's iofs source is rooted.
func VerifyEmbeddedMigrations(fsys fs.FS) error {
	migFS, err := fs.Sub(fsys, "migrations")
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationChecksum, err)
	}

	sumData, err := fs.ReadFile(migFS, "atlas.sum")
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationChecksum, err)
	}
	entries, declaredSum, err := parseSum(sumData)
	if err != nil {
		return err
	}
	if computed := sumHash(entries); computed != declaredSum {
		return fmt.Errorf("%w: atlas.sum overall hash mismatch", ErrMigrationChecksum)
	}

	// Index the listed hashes by name.
	listed := make(map[string]string, len(entries))
	for _, e := range entries {
		listed[e.name] = e.hash
	}

	// Every atlas.sum entry must reference a real .up.sql file.
	for _, e := range entries {
		if _, err := fs.Stat(migFS, e.name); err != nil {
			return fmt.Errorf("%w: listed file %q missing", ErrMigrationChecksum, e.name)
		}
	}

	// Hash-verify every *.up.sql: it must be listed and its content must match.
	upNames, err := fs.Glob(migFS, "*.up.sql")
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationChecksum, err)
	}
	sort.Strings(upNames)
	for _, name := range upNames {
		wantHash, ok := listed[name]
		if !ok {
			return fmt.Errorf("%w: unlisted .up.sql %q", ErrMigrationChecksum, name)
		}
		content, err := fs.ReadFile(migFS, name)
		if err != nil {
			return fmt.Errorf("%w: %v", ErrMigrationChecksum, err)
		}
		if got := fileHash(name, content); got != wantHash {
			return fmt.Errorf("%w: hash mismatch for %q", ErrMigrationChecksum, name)
		}
	}

	// Every .down.sql must have a paired .up.sql by base name (content is never
	// hash-verified). An orphan .down.sql fails closed.
	downNames, err := fs.Glob(migFS, "*.down.sql")
	if err != nil {
		return fmt.Errorf("%w: %v", ErrMigrationChecksum, err)
	}
	for _, downName := range downNames {
		upName := strings.TrimSuffix(downName, ".down.sql") + ".up.sql"
		if _, err := fs.Stat(migFS, upName); err != nil {
			return fmt.Errorf("%w: orphan .down.sql %q has no .up.sql pair", ErrMigrationChecksum, downName)
		}
	}

	return nil
}

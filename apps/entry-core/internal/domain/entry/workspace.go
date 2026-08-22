package entry

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"
)

var (
	ErrInvalidWorkspaceID = errors.New("invalid workspace id")
)

// WorkspaceID is a typed UUIDv7 identity for a workspace (ADR-012).
//
// Byte layout (RFC 9562): a 48-bit big-endian unix-millisecond timestamp in
// bytes 0-5, a version nibble of 7 in the high nibble of byte 6, the variant
// bits 0b10 in the high two bits of byte 8, and 62 bits of randomness in the
// remaining bits. It is a distinct domain value, intentionally separate from
// the existing stringly-typed MountRef.WorkspaceID.
type WorkspaceID [16]byte

// NewWorkspaceID generates a fresh UUIDv7 value using the current wall clock
// and crypto/rand for the random portion. The 62 random bits make collisions
// negligible, so no ordering or monotonicity guarantee is made.
func NewWorkspaceID() (WorkspaceID, error) {
	var id WorkspaceID

	now := time.Now().UnixMilli()
	// 48-bit big-endian unix-millisecond timestamp in bytes 0-5 (RFC 9562).
	// Encoded per-byte because PutUint64 would place the ~48-bit value in
	// bytes 2-7 and leave bytes 0-1 zero, and rand.Read(id[6:]) later clobbers
	// everything from byte 6 up, so the timestamp must live in bytes 0-5.
	id[0] = byte(now >> 40)
	id[1] = byte(now >> 32)
	id[2] = byte(now >> 24)
	id[3] = byte(now >> 16)
	id[4] = byte(now >> 8)
	id[5] = byte(now)

	// 48-bit timestamp occupies bytes 0-5; byte 6 high nibble is the version.
	id[6] = (id[6] & 0x0f) | 0x70
	// High two bits of byte 8 encode the RFC 9562 variant (0b10).
	id[8] = (id[8] & 0x3f) | 0x80

	if _, err := rand.Read(id[6:]); err != nil {
		return WorkspaceID{}, err
	}
	// Re-apply version/variant bits, which the random fill above may clobber.
	id[6] = (id[6] & 0x0f) | 0x70
	id[8] = (id[8] & 0x3f) | 0x80

	return id, nil
}

// ParseWorkspaceID parses a 16-byte UUIDv7 value. It rejects any input that is
// not exactly 16 bytes, does not carry version nibble 7, or does not carry the
// RFC 9562 variant.
func ParseWorkspaceID(raw []byte) (WorkspaceID, error) {
	if len(raw) != len(WorkspaceID{}) {
		return WorkspaceID{}, ErrInvalidWorkspaceID
	}
	var id WorkspaceID
	copy(id[:], raw)
	if id[6]>>4 != 0x7 {
		return WorkspaceID{}, ErrInvalidWorkspaceID
	}
	if id[8]&0xc0 != 0x80 {
		return WorkspaceID{}, ErrInvalidWorkspaceID
	}
	return id, nil
}

// Bytes returns the 16-byte wire representation of the ID.
func (id WorkspaceID) Bytes() []byte {
	out := make([]byte, len(id))
	copy(out, id[:])
	return out
}

// String returns the canonical lowercase hyphenated hex form, 8-4-4-4-12.
func (id WorkspaceID) String() string {
	buf := make([]byte, 36)
	hex.Encode(buf[0:8], id[0:4])
	buf[8] = '-'
	hex.Encode(buf[9:13], id[4:6])
	buf[13] = '-'
	hex.Encode(buf[14:18], id[6:8])
	buf[18] = '-'
	hex.Encode(buf[19:23], id[8:10])
	buf[23] = '-'
	hex.Encode(buf[24:36], id[10:16])
	return string(buf)
}

// WorkspaceContext carries the identity of the active workspace.
type WorkspaceContext struct {
	ID WorkspaceID
}

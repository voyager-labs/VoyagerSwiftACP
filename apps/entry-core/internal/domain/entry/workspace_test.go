package entry

import (
	"strings"
	"testing"
)

func TestWorkspaceIDRoundTrip(t *testing.T) {
	id, err := NewWorkspaceID()
	if err != nil {
		t.Fatalf("NewWorkspaceID() error = %v", err)
	}

	parsed, err := ParseWorkspaceID(id.Bytes())
	if err != nil {
		t.Fatalf("ParseWorkspaceID(Bytes()) error = %v", err)
	}
	if parsed != id {
		t.Fatalf("ParseWorkspaceID(Bytes()) = %v, want %v", parsed, id)
	}

	got := id.String()
	if len(got) != 36 {
		t.Fatalf("String() length = %d, want 36 (got %q)", len(got), got)
	}
	if got != strings.ToLower(got) {
		t.Fatalf("String() = %q, want lowercase", got)
	}
	// Version nibble is the high nibble of byte 6, which is the first
	// character of the third hyphen-delimited group.
	groups := strings.Split(got, "-")
	if len(groups) != 5 {
		t.Fatalf("String() = %q, want 5 hyphen-delimited groups", got)
	}
	if len(groups[0]) != 8 || len(groups[1]) != 4 || len(groups[2]) != 4 || len(groups[3]) != 4 || len(groups[4]) != 12 {
		t.Fatalf("String() = %q, group lengths not 8-4-4-4-12", got)
	}
	if groups[2][0] != '7' {
		t.Fatalf("String() = %q, version nibble = %q, want '7'", got, groups[2][0])
	}
}

func TestWorkspaceIDParseRejects(t *testing.T) {
	valid, err := NewWorkspaceID()
	if err != nil {
		t.Fatalf("NewWorkspaceID() error = %v", err)
	}
	raw := valid.Bytes()

	t.Run("wrong lengths", func(t *testing.T) {
		for _, size := range []int{15, 17} {
			slice := make([]byte, size)
			copy(slice, raw)
			if _, err := ParseWorkspaceID(slice); err == nil {
				t.Fatalf("ParseWorkspaceID(%d bytes) = nil error, want error", size)
			}
		}
	})

	t.Run("version bits not 7", func(t *testing.T) {
		bad := append([]byte(nil), raw...)
		bad[6] = bad[6]&0x0f | 0x00 // zero the high nibble -> version 0
		if _, err := ParseWorkspaceID(bad); err == nil {
			t.Fatalf("ParseWorkspaceID(version 0) = nil error, want error")
		}
	})

	t.Run("wrong variant", func(t *testing.T) {
		bad := append([]byte(nil), raw...)
		// Variant is the high bits of byte 8 (0b10xxxxxx). Flip to 0b01xxxxxx.
		bad[8] = (bad[8] & 0x3f) | 0x40
		if _, err := ParseWorkspaceID(bad); err == nil {
			t.Fatalf("ParseWorkspaceID(wrong variant) = nil error, want error")
		}
	})
}

func TestWorkspaceIDUniqueness(t *testing.T) {
	seen := make(map[WorkspaceID]struct{}, 100)
	for i := 0; i < 100; i++ {
		id, err := NewWorkspaceID()
		if err != nil {
			t.Fatalf("NewWorkspaceID() error = %v", err)
		}
		// Version nibble must be 7.
		if id[6]>>4 != 0x7 {
			t.Fatalf("version nibble = %#x, want 0x7", id[6]>>4)
		}
		// Variant bits must be 0b10 (high two bits of byte 8).
		if id[8]&0xc0 != 0x80 {
			t.Fatalf("variant bits = %#b, want 0b10", id[8]&0xc0)
		}
		if _, dup := seen[id]; dup {
			t.Fatalf("duplicate WorkspaceID generated: %v", id)
		}
		seen[id] = struct{}{}
	}
}

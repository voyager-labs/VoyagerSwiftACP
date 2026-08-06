package entry

import (
	"bytes"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

func TestCompositeCursor(t *testing.T) {
	codec, err := newCompositeCursorCodec([]byte("01234567890123456789012345678901"))
	if err != nil {
		t.Fatal(err)
	}
	queryHash := hashCursorQuery(cursorQuery{WorkspaceID: "workspace", VirtualPath: "/", PageSize: 4, RequestedProperties: []string{"title"}})
	scopeHash := hashCursorScopes(7, []cursorScope{{WorkspaceID: "workspace", MountID: "local", SourceInstanceID: localSourceID}, {WorkspaceID: "workspace", MountID: "external", SourceInstanceID: externalSourceID}})
	cursor := "opaque-child"
	states := []paginationScopeState{
		{ScopeIndex: 0, State: paginationStateContinuing, ChildCursor: &cursor},
		{ScopeIndex: 1, State: paginationStateExhausted, ExhaustedSnapshot: cursorSnapshot(t)},
	}
	token, err := codec.encode(queryHash, scopeHash, 1, states)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(token, "epc:") || len(token) > 2818 || strings.Contains(token, cursor) {
		t.Fatalf("token shape = %q", token)
	}
	decoded, err := codec.decode(token, queryHash, scopeHash, 2)
	if err != nil || decoded.RoundRobinStart != 1 || decoded.States[0].ChildCursor == nil || *decoded.States[0].ChildCursor != cursor {
		t.Fatalf("decoded = %#v, %v", decoded, err)
	}

	for name, mutate := range map[string]func() (string, [32]byte, [32]byte){
		"tamper": func() (string, [32]byte, [32]byte) {
			replacement := byte('A')
			if token[len(token)-1] == replacement {
				replacement = 'B'
			}
			return token[:len(token)-1] + string(replacement), queryHash, scopeHash
		},
		"query": func() (string, [32]byte, [32]byte) {
			changed := queryHash
			changed[0] ^= 1
			return token, changed, scopeHash
		},
		"generation": func() (string, [32]byte, [32]byte) {
			changed := scopeHash
			changed[0] ^= 1
			return token, queryHash, changed
		},
	} {
		t.Run(name, func(t *testing.T) {
			value, query, scope := mutate()
			if _, err := codec.decode(value, query, scope, 2); !errors.Is(err, ErrInvalidPageToken) {
				t.Fatalf("decode error = %v", err)
			}
		})
	}
}

func cursorSnapshot(t *testing.T) *exhaustedScopeSnapshot {
	t.Helper()
	revision, _ := domainentry.NewRevision(domainentry.RevisionStrengthUnknown, nil)
	return &exhaustedScopeSnapshot{
		SourceRevision: revision, ObservedRevision: 1, AvailabilityState: domainentry.AvailabilityStateAvailable,
		FreshnessState: domainentry.FreshnessStateCurrent, ObservedAt: time.Unix(1, 0).UTC(),
		WarningCode: source.WarningCode(""),
	}
}

func TestCompositeCursorDerivesIndependentKey(t *testing.T) {
	master := []byte("01234567890123456789012345678901")
	original := append([]byte(nil), master...)
	codec, err := newCompositeCursorCodec(master)
	if err != nil {
		t.Fatal(err)
	}
	master[0] ^= 0xff
	if bytes.Equal(codec.key, original) {
		t.Fatal("master key was used directly")
	}
	token, err := codec.encode([32]byte{1}, [32]byte{2}, 0, []paginationScopeState{{ScopeIndex: 0, State: paginationStateInitial}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := codec.decode(token, [32]byte{1}, [32]byte{2}, 1); err != nil {
		t.Fatalf("caller master mutation affected codec: %v", err)
	}
}

func TestCompositeCursorConfidentiality(t *testing.T) {
	codec, _ := newCompositeCursorCodec([]byte("01234567890123456789012345678901"))
	queryHash, scopeHash := [32]byte{1}, [32]byte{2}
	child := "confidential-child-cursor"
	token, err := codec.encode(queryHash, scopeHash, 0, []paginationScopeState{{ScopeIndex: 0, State: paginationStateContinuing, ChildCursor: &child}})
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(token, "epc:"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(decoded, []byte(child)) {
		t.Fatal("base64-decoded token exposes child cursor")
	}
}

func TestCompositeCursorRandomNonce(t *testing.T) {
	codec, _ := newCompositeCursorCodec([]byte("01234567890123456789012345678901"))
	queryHash, scopeHash := [32]byte{1}, [32]byte{2}
	states := []paginationScopeState{{ScopeIndex: 0, State: paginationStateInitial}}
	first, _ := codec.encode(queryHash, scopeHash, 0, states)
	second, _ := codec.encode(queryHash, scopeHash, 0, states)
	if first == second {
		t.Fatal("cursor nonce is deterministic")
	}
}

func TestCompositeCursorRejectsInvalidPrefix(t *testing.T) {
	codec, _ := newCompositeCursorCodec([]byte("01234567890123456789012345678901"))
	if _, err := codec.decode("invalid:AAAA", [32]byte{}, [32]byte{}, 1); !errors.Is(err, ErrInvalidPageToken) {
		t.Fatalf("invalid prefix error = %v", err)
	}
}

func TestCompositeCursorMaximumSize(t *testing.T) {
	codec, _ := newCompositeCursorCodec([]byte("01234567890123456789012345678901"))
	states := make([]paginationScopeState, 8)
	for index := range states {
		child := strings.Repeat(string(rune('a'+index)), 256)
		states[index] = paginationScopeState{ScopeIndex: uint8(index), State: paginationStateContinuing, ChildCursor: &child}
	}
	token, err := codec.encode([32]byte{1}, [32]byte{2}, 0, states)
	if err != nil {
		t.Fatal(err)
	}
	if len(token) > 2818 {
		t.Fatalf("token size = %d", len(token))
	}
}

func TestCompositeCursorTimeBounds(t *testing.T) {
	for _, observed := range []time.Time{
		time.Date(0, time.January, 1, 0, 0, 0, 123456789, time.UTC),
		time.Date(9999, time.December, 31, 23, 59, 59, 999999999, time.UTC),
	} {
		snapshot := cursorSnapshot(t)
		snapshot.ObservedAt = observed
		lastSync := observed
		staleAfter := observed
		snapshot.LastSyncAt, snapshot.StaleAfter = &lastSync, &staleAfter
		payload, err := encodeExhaustedSnapshot(*snapshot)
		if err != nil {
			t.Fatalf("encode %s: %v", observed, err)
		}
		decoded, err := decodeExhaustedSnapshot(payload)
		if err != nil {
			t.Fatalf("decode %s: %v", observed, err)
		}
		if !decoded.ObservedAt.Equal(observed) || decoded.LastSyncAt == nil || !decoded.LastSyncAt.Equal(lastSync) || decoded.StaleAfter == nil || !decoded.StaleAfter.Equal(staleAfter) {
			t.Fatalf("time round trip: want=%s got=%#v", observed, decoded)
		}
	}
}

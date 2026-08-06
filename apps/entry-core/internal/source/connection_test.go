package source

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

const connectionTestSourceID = "src:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

func TestSourceConnection(t *testing.T) {
	t.Parallel()
	observed := time.Date(2026, time.August, 3, 0, 0, 0, 0, time.UTC)
	credential, err := NewCredentialRef("credential-fixture-ref")
	if err != nil {
		t.Fatal(err)
	}
	scopes := []string{"files.read", "profile.read"}
	connection, err := NewSourceConnection("connection-1", "fakeexternal", connectionTestSourceID, AuthMethodOAuth2, ConnectionStatusConnected, &credential, scopes, observed, nil)
	if err != nil {
		t.Fatal(err)
	}
	scopes[0] = "mutated"
	if connection.Validate() != nil || connection.Scopes[0] != "files.read" {
		t.Fatalf("connection = %#v", connection)
	}
	for _, auth := range []AuthMethod{AuthMethodOAuth2, AuthMethodAPIKey, AuthMethodLocal} {
		candidateCredential := &credential
		if auth == AuthMethodLocal {
			candidateCredential = nil
		}
		if _, err := NewSourceConnection("connection", "fakeexternal", connectionTestSourceID, auth, ConnectionStatusConnected, candidateCredential, []string{}, observed, nil); err != nil {
			t.Fatalf("auth %q: %v", auth, err)
		}
	}
	for _, status := range []ConnectionStatus{ConnectionStatusDisconnected, ConnectionStatusAuthorizing, ConnectionStatusConnected, ConnectionStatusExpired, ConnectionStatusRevoked, ConnectionStatusError} {
		lastError := stringPointerForConnection("redacted_error")
		if status == ConnectionStatusConnected {
			lastError = nil
		}
		if _, err := NewSourceConnection("connection", "fakeexternal", connectionTestSourceID, AuthMethodOAuth2, status, &credential, []string{}, observed, lastError); err != nil {
			t.Fatalf("status %q: %v", status, err)
		}
	}
	if _, err := NewSourceConnection("connection", "fakeexternal", connectionTestSourceID, AuthMethodOAuth2, ConnectionStatusConnected, nil, []string{}, observed, nil); !errors.Is(err, ErrInvalidConnection) {
		t.Fatalf("missing credential error = %v", err)
	}
}

func TestConnectionResolver(t *testing.T) {
	t.Parallel()
	credential, _ := NewCredentialRef("credential-fixture-ref")
	observed := time.Date(2026, time.August, 3, 0, 0, 0, 0, time.UTC)
	connection, err := NewSourceConnection("connection-1", "fakeexternal", connectionTestSourceID, AuthMethodOAuth2, ConnectionStatusConnected, &credential, []string{"files.read"}, observed, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, state := range []ConnectionResolutionState{ConnectionResolutionConnected, ConnectionResolutionAuthRequired, ConnectionResolutionAuthExpired, ConnectionResolutionAuthRevoked, ConnectionResolutionProviderUnavailable} {
		resolver, err := NewFakeConnectionResolver(connection, state, observed.Add(time.Hour))
		if err != nil {
			t.Fatal(err)
		}
		resolution, err := resolver.Resolve(context.Background(), connectionTestSourceID, "fakeexternal")
		if err != nil || resolution.Validate() != nil || resolution.State != state {
			t.Fatalf("state %q = %#v, %v", state, resolution, err)
		}
		if (resolution.Session != nil) != (state == ConnectionResolutionConnected) {
			t.Fatalf("state %q session = %#v", state, resolution.Session)
		}
	}
	resolver, _ := NewFakeConnectionResolver(connection, ConnectionResolutionConnected, observed.Add(time.Hour))
	if _, err := resolver.Resolve(context.Background(), connectionTestSourceID, "other"); !errors.Is(err, ErrConnectionUnavailable) {
		t.Fatalf("provider mismatch = %v", err)
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := resolver.Resolve(cancelled, connectionTestSourceID, "fakeexternal"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancel = %v", err)
	}
}

func TestCredentialNonDisclosure(t *testing.T) {
	credentialLiteral := "credential-fixture-ref"
	credential, _ := NewCredentialRef(credentialLiteral)
	observed := time.Date(2026, time.August, 3, 0, 0, 0, 0, time.UTC)
	connection, _ := NewSourceConnection("connection-1", "fakeexternal", connectionTestSourceID, AuthMethodOAuth2, ConnectionStatusConnected, &credential, []string{}, observed, nil)
	resolver, _ := NewFakeConnectionResolver(connection, ConnectionResolutionConnected, observed.Add(time.Hour))
	resolution, err := resolver.Resolve(context.Background(), connectionTestSourceID, "fakeexternal")
	if err != nil {
		t.Fatal(err)
	}
	for _, rendered := range []string{fmt.Sprint(resolution), fmt.Sprintf("%#v", resolution), fmt.Sprint(resolution.Session), fmt.Sprintf("%#v", resolution.Session)} {
		if strings.Contains(rendered, credentialLiteral) || strings.Contains(strings.ToLower(rendered), "bearer") {
			t.Fatalf("credential leaked: %s", rendered)
		}
	}
	if (entry.Entry{}).Validate() == nil {
		t.Fatal("zero domain entry unexpectedly valid")
	}
}

func stringPointerForConnection(value string) *string { return &value }

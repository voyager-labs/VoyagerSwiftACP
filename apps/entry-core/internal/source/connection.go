package source

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sort"
	"time"
	"unicode/utf8"
)

var (
	ErrInvalidConnection     = errors.New("invalid source connection")
	ErrConnectionUnavailable = errors.New("connection unavailable")
)

type AuthMethod string

const (
	AuthMethodOAuth2 AuthMethod = "oauth2"
	AuthMethodAPIKey AuthMethod = "api_key"
	AuthMethodLocal  AuthMethod = "local"
)

type ConnectionStatus string

const (
	ConnectionStatusDisconnected ConnectionStatus = "disconnected"
	ConnectionStatusAuthorizing  ConnectionStatus = "authorizing"
	ConnectionStatusConnected    ConnectionStatus = "connected"
	ConnectionStatusExpired      ConnectionStatus = "expired"
	ConnectionStatusRevoked      ConnectionStatus = "revoked"
	ConnectionStatusError        ConnectionStatus = "error"
)

type CredentialRef struct{ value string }

func NewCredentialRef(value string) (CredentialRef, error) {
	if !validUTF8Bytes(value, 1, 256) {
		return CredentialRef{}, ErrInvalidConnection
	}
	return CredentialRef{value: value}, nil
}

func (CredentialRef) String() string   { return "[credential-reference]" }
func (CredentialRef) GoString() string { return "source.CredentialRef{[redacted]}" }
func (ref CredentialRef) valid() bool  { return validUTF8Bytes(ref.value, 1, 256) }

type SourceConnection struct {
	ConnectionID     string
	Provider         string
	SourceInstanceID string
	AuthMethod       AuthMethod
	Status           ConnectionStatus
	CredentialRef    *CredentialRef
	Scopes           []string
	ObservedAt       time.Time
	LastErrorCode    *string
}

func NewSourceConnection(connectionID, provider, sourceInstanceID string, authMethod AuthMethod, status ConnectionStatus, credentialRef *CredentialRef, scopes []string, observedAt time.Time, lastErrorCode *string) (SourceConnection, error) {
	value := SourceConnection{ConnectionID: connectionID, Provider: provider, SourceInstanceID: sourceInstanceID, AuthMethod: authMethod, Status: status, CredentialRef: credentialRef, Scopes: scopes, ObservedAt: observedAt.Round(0).UTC(), LastErrorCode: lastErrorCode}
	if err := value.Validate(); err != nil {
		return SourceConnection{}, err
	}
	return cloneConnection(value), nil
}

func (SourceConnection) String() string { return "SourceConnection{[redacted credential reference]}" }
func (SourceConnection) GoString() string {
	return "source.SourceConnection{[redacted credential reference]}"
}

func (connection SourceConnection) Validate() error {
	if !validUTF8Bytes(connection.ConnectionID, 1, 128) || !validASCII(connection.Provider, 1, 64) || !validSourceID(connection.SourceInstanceID) || !validConnectionAuth(connection.AuthMethod) || !validConnectionStatus(connection.Status) || !validConnectionScopes(connection.Scopes) || !validConnectionTime(connection.ObservedAt) {
		return ErrInvalidConnection
	}
	if connection.AuthMethod == AuthMethodLocal {
		if connection.CredentialRef != nil {
			return ErrInvalidConnection
		}
	} else if connection.CredentialRef == nil || !connection.CredentialRef.valid() {
		return ErrInvalidConnection
	}
	if connection.Status == ConnectionStatusConnected {
		if connection.LastErrorCode != nil {
			return ErrInvalidConnection
		}
	} else if connection.LastErrorCode != nil && !validASCII(*connection.LastErrorCode, 1, 64) {
		return ErrInvalidConnection
	}
	return nil
}

type accessAuthorization struct{}

func (accessAuthorization) String() string   { return "[authorization]" }
func (accessAuthorization) GoString() string { return "source.authorization{[redacted]}" }

type AccessSession struct {
	ConnectionID     string
	SourceInstanceID string
	Provider         string
	AuthMethod       AuthMethod
	Scopes           []string
	ExpiresAt        *time.Time
	authorization    accessAuthorization
}

func newAccessSession(connection SourceConnection, expiresAt *time.Time) (*AccessSession, error) {
	if connection.Validate() != nil || connection.Status != ConnectionStatusConnected {
		return nil, ErrConnectionUnavailable
	}
	value := &AccessSession{ConnectionID: connection.ConnectionID, SourceInstanceID: connection.SourceInstanceID, Provider: connection.Provider, AuthMethod: connection.AuthMethod, Scopes: append([]string{}, connection.Scopes...), ExpiresAt: cloneTime(expiresAt), authorization: accessAuthorization{}}
	if value.ValidateAt(connection.ObservedAt) != nil {
		return nil, ErrInvalidConnection
	}
	return value, nil
}

func (session AccessSession) Validate() error { return session.ValidateAt(time.Time{}) }
func (session AccessSession) ValidateAt(resolvedAt time.Time) error {
	if !validUTF8Bytes(session.ConnectionID, 1, 128) || !validSourceID(session.SourceInstanceID) || !validASCII(session.Provider, 1, 64) || !validConnectionAuth(session.AuthMethod) || !validConnectionScopes(session.Scopes) {
		return ErrInvalidConnection
	}
	if session.ExpiresAt != nil {
		if !validConnectionTime(*session.ExpiresAt) || (!resolvedAt.IsZero() && !session.ExpiresAt.After(resolvedAt)) {
			return ErrInvalidConnection
		}
	}
	return nil
}
func (AccessSession) String() string   { return "AccessSession{[redacted authorization]}" }
func (AccessSession) GoString() string { return "source.AccessSession{[redacted authorization]}" }

type ConnectionResolutionState string

const (
	ConnectionResolutionConnected           ConnectionResolutionState = "connected"
	ConnectionResolutionAuthRequired        ConnectionResolutionState = "auth_required"
	ConnectionResolutionAuthExpired         ConnectionResolutionState = "auth_expired"
	ConnectionResolutionAuthRevoked         ConnectionResolutionState = "auth_revoked"
	ConnectionResolutionProviderUnavailable ConnectionResolutionState = "provider_unavailable"
)

type ConnectionResolution struct {
	State        ConnectionResolutionState
	Session      *AccessSession
	ConnectionID *string
	ErrorCode    *string
	Retryable    bool
}

func (resolution ConnectionResolution) Validate() error {
	if !validResolutionState(resolution.State) || (resolution.Session != nil) != (resolution.State == ConnectionResolutionConnected) {
		return ErrInvalidConnection
	}
	if resolution.State == ConnectionResolutionConnected {
		if resolution.Session.Validate() != nil || resolution.ErrorCode != nil || resolution.Retryable {
			return ErrInvalidConnection
		}
	} else if resolution.ErrorCode != nil && !validASCII(*resolution.ErrorCode, 1, 64) {
		return ErrInvalidConnection
	}
	if resolution.ConnectionID != nil && !validUTF8Bytes(*resolution.ConnectionID, 1, 128) {
		return ErrInvalidConnection
	}
	return nil
}
func (resolution ConnectionResolution) String() string {
	return fmt.Sprintf("ConnectionResolution{state:%s}", resolution.State)
}
func (resolution ConnectionResolution) GoString() string { return resolution.String() }

type ConnectionResolver interface {
	Resolve(context.Context, string, string) (ConnectionResolution, error)
}

type FakeConnectionResolver struct {
	connection SourceConnection
	state      ConnectionResolutionState
	expiresAt  *time.Time
}

func NewFakeConnectionResolver(connection SourceConnection, state ConnectionResolutionState, expiresAt time.Time) (*FakeConnectionResolver, error) {
	if connection.Validate() != nil || !validResolutionState(state) {
		return nil, ErrInvalidConnection
	}
	var expiry *time.Time
	if state == ConnectionResolutionConnected && !expiresAt.IsZero() {
		canonical := expiresAt.Round(0).UTC()
		expiry = &canonical
	}
	return &FakeConnectionResolver{connection: cloneConnection(connection), state: state, expiresAt: expiry}, nil
}

func (resolver *FakeConnectionResolver) Resolve(ctx context.Context, sourceInstanceID, provider string) (ConnectionResolution, error) {
	if ctx == nil {
		return ConnectionResolution{}, ErrConnectionUnavailable
	}
	if err := ctx.Err(); err != nil {
		return ConnectionResolution{}, err
	}
	if resolver == nil || resolver.connection.Validate() != nil || sourceInstanceID != resolver.connection.SourceInstanceID || provider != resolver.connection.Provider {
		return ConnectionResolution{}, ErrConnectionUnavailable
	}
	connectionID := resolver.connection.ConnectionID
	resolution := ConnectionResolution{State: resolver.state, ConnectionID: &connectionID}
	switch resolver.state {
	case ConnectionResolutionConnected:
		session, err := newAccessSession(resolver.connection, resolver.expiresAt)
		if err != nil {
			return ConnectionResolution{}, ErrConnectionUnavailable
		}
		resolution.Session = session
	case ConnectionResolutionAuthRequired:
		resolution.ErrorCode = connectionString("auth_required")
	case ConnectionResolutionAuthExpired:
		resolution.ErrorCode = connectionString("auth_expired")
	case ConnectionResolutionAuthRevoked:
		resolution.ErrorCode = connectionString("auth_revoked")
	case ConnectionResolutionProviderUnavailable:
		resolution.ErrorCode = connectionString("provider_unavailable")
		resolution.Retryable = true
	default:
		return ConnectionResolution{}, ErrConnectionUnavailable
	}
	if resolution.Validate() != nil {
		return ConnectionResolution{}, ErrConnectionUnavailable
	}
	return cloneResolution(resolution), nil
}

func cloneResolution(value ConnectionResolution) ConnectionResolution {
	value.ConnectionID = cloneString(value.ConnectionID)
	value.ErrorCode = cloneString(value.ErrorCode)
	if value.Session != nil {
		copy := *value.Session
		copy.Scopes = append([]string{}, value.Session.Scopes...)
		copy.ExpiresAt = cloneTime(value.Session.ExpiresAt)
		value.Session = &copy
	}
	return value
}
func cloneConnection(value SourceConnection) SourceConnection {
	value.CredentialRef = cloneCredentialRef(value.CredentialRef)
	value.Scopes = append([]string{}, value.Scopes...)
	value.LastErrorCode = cloneString(value.LastErrorCode)
	return value
}
func cloneCredentialRef(value *CredentialRef) *CredentialRef {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
func connectionString(value string) *string { return &value }
func validConnectionAuth(value AuthMethod) bool {
	return value == AuthMethodOAuth2 || value == AuthMethodAPIKey || value == AuthMethodLocal
}
func validConnectionStatus(value ConnectionStatus) bool {
	switch value {
	case ConnectionStatusDisconnected, ConnectionStatusAuthorizing, ConnectionStatusConnected, ConnectionStatusExpired, ConnectionStatusRevoked, ConnectionStatusError:
		return true
	}
	return false
}
func validResolutionState(value ConnectionResolutionState) bool {
	switch value {
	case ConnectionResolutionConnected, ConnectionResolutionAuthRequired, ConnectionResolutionAuthExpired, ConnectionResolutionAuthRevoked, ConnectionResolutionProviderUnavailable:
		return true
	}
	return false
}
func validConnectionTime(value time.Time) bool {
	return !value.IsZero() && value.Location() == time.UTC && value.Year() >= 0 && value.Year() <= 9999
}
func validConnectionScopes(values []string) bool {
	if values == nil || len(values) > 64 || !sort.StringsAreSorted(values) {
		return false
	}
	for index, value := range values {
		if !validASCII(value, 1, 128) || index > 0 && values[index-1] == value {
			return false
		}
	}
	return true
}
func typedNilConnectionResolver(value ConnectionResolver) bool {
	if value == nil {
		return true
	}
	ref := reflect.ValueOf(value)
	switch ref.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return ref.IsNil()
	}
	return false
}
func validConnectionText(value string, min, max int) bool {
	return utf8.ValidString(value) && len(value) >= min && len(value) <= max
}

package entry

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"io"
	"strings"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

const (
	compositeCursorPrefix       = "epc:"
	maximumCompositeCursorBytes = 2818
	compositeCursorKeyLabel     = "entry-core/composite-cursor/aes-256-gcm"
)

type paginationState byte

const (
	paginationStateInitial paginationState = iota
	paginationStateContinuing
	paginationStateExhausted
)

type cursorQuery struct {
	WorkspaceID         string
	MountID             string
	SourceInstanceID    string
	VirtualPath         string
	ParentEntryID       string
	ParentSourceID      string
	ParentObjectKey     string
	ParentResourceType  string
	ParentLocator       string
	ParentStrength      string
	PageSize            int
	RequestedProperties []string
}

type cursorScope struct {
	WorkspaceID      string
	MountID          string
	SourceInstanceID string
}

type exhaustedScopeSnapshot struct {
	SourceRevision    domainentry.Revision
	ObservedRevision  uint64
	AvailabilityState domainentry.AvailabilityState
	FreshnessState    domainentry.FreshnessState
	ObservedAt        time.Time
	LastSyncAt        *time.Time
	StaleAfter        *time.Time
	SourceErrorCode   source.SourceErrorCode
	WarningCode       source.WarningCode
	SourceRetryable   bool
	WarningRetryable  bool
}

type paginationScopeState struct {
	ScopeIndex        uint8
	State             paginationState
	ChildCursor       *string
	ExhaustedSnapshot *exhaustedScopeSnapshot
}

type decodedCompositeCursor struct {
	RoundRobinStart uint8
	States          []paginationScopeState
}

type compositeCursorCodec struct {
	key  []byte
	aead cipher.AEAD
}

func newCompositeCursorCodec(master []byte) (*compositeCursorCodec, error) {
	if len(master) != sha256.Size {
		return nil, ErrInvalidService
	}
	copied := append([]byte(nil), master...)
	material := binary.BigEndian.AppendUint64(nil, uint64(len(compositeCursorKeyLabel)))
	material = append(material, compositeCursorKeyLabel...)
	mac := hmac.New(sha256.New, copied)
	_, _ = mac.Write(material)
	key := mac.Sum(nil)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, ErrInvalidService
	}
	aead, err := cipher.NewGCM(block)
	if err != nil || aead.NonceSize() != 12 || aead.Overhead() != 16 {
		return nil, ErrInvalidService
	}
	return &compositeCursorCodec{key: append([]byte(nil), key...), aead: aead}, nil
}

func (codec *compositeCursorCodec) encode(queryHash, scopeHash [sha256.Size]byte, roundRobinStart uint8, states []paginationScopeState) (string, error) {
	if codec == nil || len(codec.key) != sha256.Size || codec.aead == nil || len(states) < 1 || len(states) > 8 || int(roundRobinStart) >= len(states) {
		return "", ErrInvalidPageToken
	}
	plaintext := []byte{roundRobinStart, byte(len(states))}
	for index, state := range states {
		if int(state.ScopeIndex) != index {
			return "", ErrInvalidPageToken
		}
		union, err := encodeCursorState(state)
		if err != nil || len(union) > 256 {
			return "", ErrInvalidPageToken
		}
		plaintext = append(plaintext, state.ScopeIndex, byte(state.State), byte(len(union)>>8), byte(len(union)))
		plaintext = append(plaintext, union...)
	}
	nonce := make([]byte, codec.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", ErrInvalidPageToken
	}
	aad := cursorAAD(queryHash, scopeHash)
	sealed := codec.aead.Seal(nil, nonce, plaintext, aad)
	raw := append(append([]byte(nil), nonce...), sealed...)
	token := compositeCursorPrefix + base64.RawURLEncoding.EncodeToString(raw)
	if len(token) > maximumCompositeCursorBytes {
		return "", ErrInvalidPageToken
	}
	return token, nil
}

func (codec *compositeCursorCodec) decode(token string, queryHash, scopeHash [sha256.Size]byte, scopeCount int) (decodedCompositeCursor, error) {
	if codec == nil || len(codec.key) != sha256.Size || codec.aead == nil || len(token) <= len(compositeCursorPrefix) || len(token) > maximumCompositeCursorBytes || scopeCount < 1 || scopeCount > 8 || !strings.HasPrefix(token, compositeCursorPrefix) {
		return decodedCompositeCursor{}, ErrInvalidPageToken
	}
	encoded := token[len(compositeCursorPrefix):]
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || base64.RawURLEncoding.EncodeToString(raw) != encoded || len(raw) < codec.aead.NonceSize()+codec.aead.Overhead()+2 {
		return decodedCompositeCursor{}, ErrInvalidPageToken
	}
	nonce := raw[:codec.aead.NonceSize()]
	plaintext, err := codec.aead.Open(nil, nonce, raw[codec.aead.NonceSize():], cursorAAD(queryHash, scopeHash))
	if err != nil || len(plaintext) < 2 {
		return decodedCompositeCursor{}, ErrInvalidPageToken
	}
	roundRobinStart := plaintext[0]
	count := int(plaintext[1])
	if count != scopeCount || int(roundRobinStart) >= count {
		return decodedCompositeCursor{}, ErrInvalidPageToken
	}
	states := make([]paginationScopeState, 0, count)
	offset := 2
	for index := range count {
		if offset+4 > len(plaintext) {
			return decodedCompositeCursor{}, ErrInvalidPageToken
		}
		scopeIndex := plaintext[offset]
		state := paginationState(plaintext[offset+1])
		length := int(binary.BigEndian.Uint16(plaintext[offset+2 : offset+4]))
		offset += 4
		if int(scopeIndex) != index || length > 256 || offset+length > len(plaintext) {
			return decodedCompositeCursor{}, ErrInvalidPageToken
		}
		row, err := decodeCursorState(scopeIndex, state, plaintext[offset:offset+length])
		if err != nil {
			return decodedCompositeCursor{}, ErrInvalidPageToken
		}
		states = append(states, row)
		offset += length
	}
	if offset != len(plaintext) {
		return decodedCompositeCursor{}, ErrInvalidPageToken
	}
	return decodedCompositeCursor{RoundRobinStart: roundRobinStart, States: states}, nil
}

func cursorAAD(queryHash, scopeHash [sha256.Size]byte) []byte {
	aad := make([]byte, 0, sha256.Size*2)
	aad = append(aad, queryHash[:]...)
	return append(aad, scopeHash[:]...)
}

func encodeCursorState(state paginationScopeState) ([]byte, error) {
	switch state.State {
	case paginationStateInitial:
		if state.ChildCursor != nil || state.ExhaustedSnapshot != nil {
			return nil, ErrInvalidPageToken
		}
		return []byte{}, nil
	case paginationStateContinuing:
		if state.ChildCursor == nil || state.ExhaustedSnapshot != nil || !validOpaqueASCII(*state.ChildCursor, 1, 256) {
			return nil, ErrInvalidPageToken
		}
		return []byte(*state.ChildCursor), nil
	case paginationStateExhausted:
		if state.ChildCursor != nil || state.ExhaustedSnapshot == nil {
			return nil, ErrInvalidPageToken
		}
		return encodeExhaustedSnapshot(*state.ExhaustedSnapshot)
	default:
		return nil, ErrInvalidPageToken
	}
}

func decodeCursorState(index uint8, state paginationState, payload []byte) (paginationScopeState, error) {
	row := paginationScopeState{ScopeIndex: index, State: state}
	switch state {
	case paginationStateInitial:
		if len(payload) != 0 {
			return paginationScopeState{}, ErrInvalidPageToken
		}
	case paginationStateContinuing:
		value := string(payload)
		if !validOpaqueASCII(value, 1, 256) {
			return paginationScopeState{}, ErrInvalidPageToken
		}
		row.ChildCursor = &value
	case paginationStateExhausted:
		snapshot, err := decodeExhaustedSnapshot(payload)
		if err != nil {
			return paginationScopeState{}, err
		}
		row.ExhaustedSnapshot = &snapshot
	default:
		return paginationScopeState{}, ErrInvalidPageToken
	}
	return row, nil
}

func encodeExhaustedSnapshot(snapshot exhaustedScopeSnapshot) ([]byte, error) {
	if snapshot.SourceRevision.Validate() != nil || snapshot.SourceRevision.Strength == domainentry.RevisionStrengthObserved || snapshot.ObservedRevision == 0 || !validCursorAvailability(snapshot.AvailabilityState) || !validCursorFreshness(snapshot.FreshnessState) || !validCursorTime(snapshot.ObservedAt) {
		return nil, ErrInvalidPageToken
	}
	token := ""
	if snapshot.SourceRevision.Token != nil {
		token = *snapshot.SourceRevision.Token
	}
	if !validOpaqueASCII(token, 0, 128) {
		return nil, ErrInvalidPageToken
	}
	flags := byte(0)
	if snapshot.LastSyncAt != nil {
		if !validCursorTime(*snapshot.LastSyncAt) {
			return nil, ErrInvalidPageToken
		}
		flags |= 1
	}
	if snapshot.StaleAfter != nil {
		if !validCursorTime(*snapshot.StaleAfter) || snapshot.StaleAfter.Before(snapshot.ObservedAt) {
			return nil, ErrInvalidPageToken
		}
		flags |= 2
	}
	if snapshot.SourceRetryable {
		flags |= 4
	}
	if snapshot.WarningRetryable {
		flags |= 8
	}
	result := []byte{revisionStrengthByte(snapshot.SourceRevision.Strength), byte(len(token))}
	if result[0] == 0 {
		return nil, ErrInvalidPageToken
	}
	result = append(result, token...)
	result = binary.BigEndian.AppendUint64(result, snapshot.ObservedRevision)
	result = append(result, availabilityByte(snapshot.AvailabilityState), freshnessByte(snapshot.FreshnessState))
	result = appendCursorTime(result, snapshot.ObservedAt)
	result = append(result, flags)
	if snapshot.LastSyncAt != nil {
		result = appendCursorTime(result, *snapshot.LastSyncAt)
	}
	if snapshot.StaleAfter != nil {
		result = appendCursorTime(result, *snapshot.StaleAfter)
	}
	result = append(result, sourceErrorByte(snapshot.SourceErrorCode), warningByte(snapshot.WarningCode))
	if len(result) > 180 {
		return nil, ErrInvalidPageToken
	}
	return result, nil
}

func decodeExhaustedSnapshot(payload []byte) (exhaustedScopeSnapshot, error) {
	if len(payload) < 2+8+2+12+1+2 {
		return exhaustedScopeSnapshot{}, ErrInvalidPageToken
	}
	strength := revisionStrengthFromByte(payload[0])
	tokenLength := int(payload[1])
	offset := 2
	if strength == "" || tokenLength > 128 || offset+tokenLength+25 > len(payload) {
		return exhaustedScopeSnapshot{}, ErrInvalidPageToken
	}
	var token *string
	if tokenLength > 0 {
		value := string(payload[offset : offset+tokenLength])
		if !validOpaqueASCII(value, 1, 128) {
			return exhaustedScopeSnapshot{}, ErrInvalidPageToken
		}
		token = &value
	}
	offset += tokenLength
	revision, err := domainentry.NewRevision(strength, token)
	if err != nil || revision.Strength == domainentry.RevisionStrengthObserved {
		return exhaustedScopeSnapshot{}, ErrInvalidPageToken
	}
	observedRevision := binary.BigEndian.Uint64(payload[offset : offset+8])
	offset += 8
	availability := availabilityFromByte(payload[offset])
	offset++
	freshness := freshnessFromByte(payload[offset])
	offset++
	observedAt, err := readCursorTime(payload, &offset)
	if err != nil {
		return exhaustedScopeSnapshot{}, err
	}
	flags := payload[offset]
	offset++
	if flags&0xf0 != 0 || observedRevision == 0 || availability == "" || freshness == "" {
		return exhaustedScopeSnapshot{}, ErrInvalidPageToken
	}
	readTime := func(bit byte) (*time.Time, error) {
		if flags&bit == 0 {
			return nil, nil
		}
		value, err := readCursorTime(payload, &offset)
		if err != nil {
			return nil, err
		}
		return &value, nil
	}
	lastSync, err := readTime(1)
	if err != nil {
		return exhaustedScopeSnapshot{}, err
	}
	staleAfter, err := readTime(2)
	if err != nil {
		return exhaustedScopeSnapshot{}, err
	}
	if offset+2 != len(payload) {
		return exhaustedScopeSnapshot{}, ErrInvalidPageToken
	}
	errorCode := sourceErrorFromByte(payload[offset])
	offset++
	warningCode := warningFromByte(payload[offset])
	if payload[offset-1] != 0 && errorCode == "" || payload[offset] != 0 && warningCode == "" {
		return exhaustedScopeSnapshot{}, ErrInvalidPageToken
	}
	return exhaustedScopeSnapshot{SourceRevision: revision, ObservedRevision: observedRevision, AvailabilityState: availability, FreshnessState: freshness, ObservedAt: observedAt, LastSyncAt: lastSync, StaleAfter: staleAfter, SourceErrorCode: errorCode, WarningCode: warningCode, SourceRetryable: flags&4 != 0, WarningRetryable: flags&8 != 0}, nil
}

func appendCursorTime(target []byte, value time.Time) []byte {
	target = binary.BigEndian.AppendUint64(target, uint64(value.Unix()))
	return binary.BigEndian.AppendUint32(target, uint32(value.Nanosecond()))
}

func readCursorTime(payload []byte, offset *int) (time.Time, error) {
	if *offset+12 > len(payload) {
		return time.Time{}, ErrInvalidPageToken
	}
	seconds := int64(binary.BigEndian.Uint64(payload[*offset : *offset+8]))
	nanoseconds := binary.BigEndian.Uint32(payload[*offset+8 : *offset+12])
	*offset += 12
	if nanoseconds >= 1_000_000_000 {
		return time.Time{}, ErrInvalidPageToken
	}
	value := time.Unix(seconds, int64(nanoseconds)).UTC()
	if !validCursorTime(value) {
		return time.Time{}, ErrInvalidPageToken
	}
	return value, nil
}

func hashCursorQuery(query cursorQuery) [sha256.Size]byte {
	payload := make([]byte, 0)
	for _, value := range []string{query.WorkspaceID, query.MountID, query.SourceInstanceID, query.VirtualPath, query.ParentEntryID, query.ParentSourceID, query.ParentObjectKey, query.ParentResourceType, query.ParentLocator, query.ParentStrength} {
		payload = appendCursorString(payload, value)
	}
	payload = binary.BigEndian.AppendUint64(payload, uint64(query.PageSize))
	payload = binary.BigEndian.AppendUint64(payload, uint64(len(query.RequestedProperties)))
	for _, property := range query.RequestedProperties {
		payload = appendCursorString(payload, property)
	}
	return sha256.Sum256(payload)
}

func hashCursorScopes(generation uint64, scopes []cursorScope) [sha256.Size]byte {
	payload := binary.BigEndian.AppendUint64(nil, generation)
	payload = binary.BigEndian.AppendUint64(payload, uint64(len(scopes)))
	for _, scope := range scopes {
		for _, value := range []string{scope.WorkspaceID, scope.MountID, scope.SourceInstanceID} {
			payload = appendCursorString(payload, value)
		}
	}
	return sha256.Sum256(payload)
}

func appendCursorString(destination []byte, value string) []byte {
	destination = binary.BigEndian.AppendUint64(destination, uint64(len(value)))
	return append(destination, value...)
}

func validOpaqueASCII(value string, minimum, maximum int) bool {
	if len(value) < minimum || len(value) > maximum {
		return false
	}
	for index := range len(value) {
		if value[index] > 0x7f {
			return false
		}
	}
	return true
}

func validCursorTime(value time.Time) bool {
	return value.Location() == time.UTC && value.Year() >= 0 && value.Year() <= 9999
}
func validCursorAvailability(value domainentry.AvailabilityState) bool {
	return availabilityByte(value) != 0
}
func validCursorFreshness(value domainentry.FreshnessState) bool { return freshnessByte(value) != 0 }

func revisionStrengthByte(value domainentry.RevisionStrength) byte {
	switch value {
	case domainentry.RevisionStrengthProvider:
		return 1
	case domainentry.RevisionStrengthMetadata:
		return 2
	case domainentry.RevisionStrengthUnknown:
		return 3
	}
	return 0
}
func revisionStrengthFromByte(value byte) domainentry.RevisionStrength {
	switch value {
	case 1:
		return domainentry.RevisionStrengthProvider
	case 2:
		return domainentry.RevisionStrengthMetadata
	case 3:
		return domainentry.RevisionStrengthUnknown
	}
	return ""
}
func availabilityByte(value domainentry.AvailabilityState) byte {
	switch value {
	case domainentry.AvailabilityStateAvailable:
		return 1
	case domainentry.AvailabilityStateLoading:
		return 2
	case domainentry.AvailabilityStateStale:
		return 3
	case domainentry.AvailabilityStateOffline:
		return 4
	case domainentry.AvailabilityStatePermissionDenied:
		return 5
	case domainentry.AvailabilityStateSourceDeleted:
		return 6
	case domainentry.AvailabilityStateUnmounted:
		return 7
	case domainentry.AvailabilityStateReadOnly:
		return 8
	case domainentry.AvailabilityStateError:
		return 9
	}
	return 0
}
func availabilityFromByte(value byte) domainentry.AvailabilityState {
	for _, state := range []domainentry.AvailabilityState{domainentry.AvailabilityStateAvailable, domainentry.AvailabilityStateLoading, domainentry.AvailabilityStateStale, domainentry.AvailabilityStateOffline, domainentry.AvailabilityStatePermissionDenied, domainentry.AvailabilityStateSourceDeleted, domainentry.AvailabilityStateUnmounted, domainentry.AvailabilityStateReadOnly, domainentry.AvailabilityStateError} {
		if availabilityByte(state) == value {
			return state
		}
	}
	return ""
}
func freshnessByte(value domainentry.FreshnessState) byte {
	switch value {
	case domainentry.FreshnessStateCurrent:
		return 1
	case domainentry.FreshnessStateStale:
		return 2
	case domainentry.FreshnessStateUnknown:
		return 3
	}
	return 0
}
func freshnessFromByte(value byte) domainentry.FreshnessState {
	switch value {
	case 1:
		return domainentry.FreshnessStateCurrent
	case 2:
		return domainentry.FreshnessStateStale
	case 3:
		return domainentry.FreshnessStateUnknown
	}
	return ""
}
func sourceErrorByte(value source.SourceErrorCode) byte {
	switch value {
	case "":
		return 0
	case source.SourceErrorCodeEntryNotFound:
		return 1
	case source.SourceErrorCodeSourceUnavailable:
		return 2
	case source.SourceErrorCodePermissionDenied:
		return 3
	case source.SourceErrorCodeSourceDeleted:
		return 4
	case source.SourceErrorCodeAdapterFailure:
		return 5
	}
	return 255
}
func sourceErrorFromByte(value byte) source.SourceErrorCode {
	switch value {
	case 0:
		return ""
	case 1:
		return source.SourceErrorCodeEntryNotFound
	case 2:
		return source.SourceErrorCodeSourceUnavailable
	case 3:
		return source.SourceErrorCodePermissionDenied
	case 4:
		return source.SourceErrorCodeSourceDeleted
	case 5:
		return source.SourceErrorCodeAdapterFailure
	}
	return ""
}
func warningByte(value source.WarningCode) byte {
	switch value {
	case "":
		return 0
	case source.WarningCodeStaleSnapshot:
		return 1
	case source.WarningCodeSourceOffline:
		return 2
	case source.WarningCodeSourceUnavailable:
		return 3
	case source.WarningCodePermissionDenied:
		return 4
	case source.WarningCodeSourceDeleted:
		return 5
	case source.WarningCodeAdapterFailure:
		return 6
	case source.WarningCodePartialResult:
		return 7
	}
	return 255
}
func warningFromByte(value byte) source.WarningCode {
	switch value {
	case 0:
		return ""
	case 1:
		return source.WarningCodeStaleSnapshot
	case 2:
		return source.WarningCodeSourceOffline
	case 3:
		return source.WarningCodeSourceUnavailable
	case 4:
		return source.WarningCodePermissionDenied
	case 5:
		return source.WarningCodeSourceDeleted
	case 6:
		return source.WarningCodeAdapterFailure
	case 7:
		return source.WarningCodePartialResult
	}
	return ""
}

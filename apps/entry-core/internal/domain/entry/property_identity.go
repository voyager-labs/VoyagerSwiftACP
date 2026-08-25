package entry

import (
	"crypto/sha1"
	"encoding/hex"
	"errors"
)

var (
	ErrInvalidPropertyID          = errors.New("invalid property id")
	ErrInvalidPropertyIDText      = errors.New("invalid property id text")
	ErrInvalidPropertyIDScheme    = errors.New("invalid property identity scheme")
	ErrPropertyIDSchemeMismatch   = errors.New("property id scheme mismatch")
	ErrInvalidRegistryPropertyKey = errors.New("invalid registry property key")

	ErrInvalidPropertyOptionID         = errors.New("invalid property option id")
	ErrInvalidPropertyOptionIDText     = errors.New("invalid property option id text")
	ErrPropertyOptionIDVersionMismatch = errors.New("property option id version mismatch")
)

// PropertyID is a typed 16-byte UUID identity for a Voyager Property (ADR-015).
//
// Byte layout follows RFC 9562: a version nibble in the high nibble of byte 6
// and the RFC 4122 variant bits 0b10 in the high two bits of byte 8. Unlike
// WorkspaceID, PropertyID carries no timestamp contract of its own; the UUID
// version is validated against an explicit PropertyIdentityScheme rather than
// being inferred from a broad origin (future curated presets may be
// Voyager-issued UUIDv7 while Registry-backed rows stay UUIDv5).
type PropertyID [16]byte

// ParsePropertyID parses a canonical lowercase hyphenated UUID text form
// (8-4-4-4-12) into a typed PropertyID. It rejects any text that is not exactly
// 36 characters, is not valid lowercase hex in canonical form, or does not
// carry the RFC 4122 variant. Version nibble is preserved (5 or 7) and later
// checked against the owning PropertyIdentityScheme.
func ParsePropertyID(text string) (PropertyID, error) {
	return parseUUIDText(text)
}

// parseUUIDText는 정규 소문자 하이픈 UUID 텍스트(8-4-4-4-12)를 16바이트로 파싱하고
// RFC 9562 variant 비트만 검사한다. 버전 니블은 보존되며 소유자 유형이 요구하는
// scheme 검사에서 별도로 확인된다.
func parseUUIDText(text string) (PropertyID, error) {
	if len(text) != 36 {
		return PropertyID{}, ErrInvalidPropertyIDText
	}
	var id PropertyID
	group := [5]int{8, 4, 4, 4, 12}
	charOffset := 0
	byteOffset := 0
	for index, length := range group {
		raw := text[charOffset : charOffset+length]
		if index > 0 && text[charOffset-1] != '-' {
			return PropertyID{}, ErrInvalidPropertyIDText
		}
		if !isLowerHex(raw) {
			return PropertyID{}, ErrInvalidPropertyIDText
		}
		decoded, err := hex.DecodeString(raw)
		if err != nil {
			return PropertyID{}, ErrInvalidPropertyIDText
		}
		copy(id[byteOffset:], decoded)
		charOffset += length + 1
		byteOffset += length / 2
	}
	// RFC 9562 variant bits 0b10 in byte 8.
	if id[8]&0xc0 != 0x80 {
		return PropertyID{}, ErrInvalidPropertyIDText
	}
	return id, nil
}

func isLowerHex(value string) bool {
	for index := range len(value) {
		ch := value[index]
		if (ch < '0' || ch > '9') && (ch < 'a' || ch > 'f') {
			return false
		}
	}
	return true
}

// MustPropertyID parses text and panics on error. It exists only for immutable
// package-level literals and test fixtures; production code must use
// ParsePropertyID and handle the error.
func MustPropertyID(text string) PropertyID {
	id, err := ParsePropertyID(text)
	if err != nil {
		panic(err)
	}
	return id
}

// Bytes returns the 16-byte wire representation of the ID.
func (id PropertyID) Bytes() []byte {
	out := make([]byte, len(id))
	copy(out, id[:])
	return out
}

// String returns the canonical lowercase hyphenated hex form, 8-4-4-4-12.
func (id PropertyID) String() string {
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

// version returns the RFC 9562 version nibble (high nibble of byte 6).
func (id PropertyID) version() byte {
	return id[6] >> 4
}

// valid reports whether the ID is non-nil and carries the RFC 9562 variant.
func (id PropertyID) valid() bool {
	if id == (PropertyID{}) {
		return false
	}
	return id[8]&0xc0 == 0x80
}

// PropertyIdentityScheme is an explicit declaration of the UUID version a
// PropertyID must carry. It is never inferred from a broad origin because
// future curated presets may be Voyager-issued UUIDv7.
type PropertyIdentityScheme string

const (
	// PropertyIdentitySchemeRegistryDerived marks a deterministic UUIDv5
	// derived from the frozen Registry namespace and an exact category.key.
	PropertyIdentitySchemeRegistryDerived PropertyIdentityScheme = "registry_derived"
	// PropertyIdentitySchemeVoyagerIssued marks a Voyager-issued UUIDv7.
	PropertyIdentitySchemeVoyagerIssued PropertyIdentityScheme = "voyager_issued"
)

func (scheme PropertyIdentityScheme) valid() bool {
	switch scheme {
	case PropertyIdentitySchemeRegistryDerived, PropertyIdentitySchemeVoyagerIssued:
		return true
	default:
		return false
	}
}

// acceptsVersion reports whether the scheme allows the given RFC 9562 version
// nibble.
func (scheme PropertyIdentityScheme) acceptsVersion(version byte) bool {
	switch scheme {
	case PropertyIdentitySchemeRegistryDerived:
		return version == 5
	case PropertyIdentitySchemeVoyagerIssued:
		return version == 7
	default:
		return false
	}
}

// RegistryPropertyNamespace is the frozen UUIDv5 namespace for Registry-backed
// built-in Properties. It is derived once as UUIDv5(RFC URL namespace,
// "https://github.com/voyager-labs/voyager-app/entry-property") and fixed as a
// literal; runtime never recomputes it.
var RegistryPropertyNamespace = MustPropertyID("4e25d517-09e2-5cbb-83f9-ed2290161e08")

// RegistryPropertyID derives the deterministic UUIDv5 PropertyID for an exact
// immutable category.key under the frozen Registry namespace. The key is a
// case-preserving exact identity input; label/description/alias/version never
// participate in the derivation.
func RegistryPropertyID(categoryKey string) (PropertyID, error) {
	if !validUTF8Bytes(categoryKey, 1, 256) {
		return PropertyID{}, ErrInvalidRegistryPropertyKey
	}
	h := sha1.New()
	h.Write(RegistryPropertyNamespace[:])
	h.Write([]byte(categoryKey))
	sum := h.Sum(nil)
	var id PropertyID
	copy(id[:], sum[:16])
	// version 5 + RFC 4122 variant.
	id[6] = (id[6] & 0x0f) | 0x50
	id[8] = (id[8] & 0x3f) | 0x80
	return id, nil
}

// PropertyOptionID는 select option의 역할별 typed UUIDv7 identity다. Option은
// 항상 Voyager 발급 UUIDv7이다(Registry 유도 v5 없음). Byte layout은 RFC 9562를
// 따르며 version 니블 7과 RFC 4122 variant를 강제한다.
type PropertyOptionID [16]byte

// ParsePropertyOptionID는 정규 소문자 하이픈 UUID 텍스트를 파싱하고 version 7과
// RFC 4122 variant를 강제한다. 비정상 텍스트는 ErrInvalidPropertyOptionIDText,
// 버전 불일치는 ErrPropertyOptionIDVersionMismatch로 실패 닫기한다.
func ParsePropertyOptionID(text string) (PropertyOptionID, error) {
	parsed, err := parseUUIDText(text)
	if err != nil {
		return PropertyOptionID{}, ErrInvalidPropertyOptionIDText
	}
	if parsed.version() != 7 {
		return PropertyOptionID{}, ErrPropertyOptionIDVersionMismatch
	}
	return PropertyOptionID(parsed), nil
}

// MustPropertyOptionID는 파싱 실패 시 panic한다. package 수준 불변 리터럴과 테스트
// 픽스처 전용이며 production 코드는 ParsePropertyOptionID와 오류 처리를 쓴다.
func MustPropertyOptionID(text string) PropertyOptionID {
	id, err := ParsePropertyOptionID(text)
	if err != nil {
		panic(err)
	}
	return id
}

func (id PropertyOptionID) Bytes() []byte {
	out := make([]byte, len(id))
	copy(out, id[:])
	return out
}

func (id PropertyOptionID) String() string {
	return PropertyID(id).String()
}

func (id PropertyOptionID) version() byte {
	return id[6] >> 4
}

// valid은 ID가 영값이 아니고 version 7과 RFC 9562 variant를 만족하는지 보고한다.
func (id PropertyOptionID) valid() bool {
	if id == (PropertyOptionID{}) {
		return false
	}
	return id.version() == 7 && id[8]&0xc0 == 0x80
}

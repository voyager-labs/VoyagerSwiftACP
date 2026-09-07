package entry

import (
	"errors"
	"strings"
	"testing"
)

// testPropertyOptionV7Texts는 테스트 전용 UUIDv7 option identity 리터럴이다.
var (
	testPropertyOptionV7A = "0198f0a2-7b3c-7456-9abc-def012345678"
	testPropertyOptionV7B = "0198f0a2-7b3c-7abc-abcd-def012345678"
	testPropertyOptionV5  = RegistryPropertyNamespace.String()
)

func TestPropertyOptionIDParseRoundTrip(t *testing.T) {
	// Given: 정규 형식의 UUIDv7 텍스트
	// When: ParsePropertyOptionID로 파싱하면
	parsed, err := ParsePropertyOptionID(testPropertyOptionV7A)
	// Then: 오류 없이 동일한 텍스트로 왕복한다.
	if err != nil {
		t.Fatalf("ParsePropertyOptionID(%q) returned error: %v", testPropertyOptionV7A, err)
	}
	if got := parsed.String(); got != testPropertyOptionV7A {
		t.Fatalf("round trip mismatch: got %q want %q", got, testPropertyOptionV7A)
	}
	if !parsed.valid() {
		t.Fatal("parsed option id must be valid")
	}
	if MustPropertyOptionID(testPropertyOptionV7B) != MustPropertyOptionID(testPropertyOptionV7B) {
		t.Fatal("identical texts must parse to equal values")
	}
}

func TestPropertyOptionIDRejectsMalformed(t *testing.T) {
	cases := map[string]string{
		"empty":            "",
		"short":            "0198f0a2-7b3c-7456-9abc-def01234567",
		"upper_hex":        strings.ToUpper(testPropertyOptionV7A),
		"missing_hyphens":  strings.ReplaceAll(testPropertyOptionV7A, "-", ""),
		"non_hex":          "0198f0a2-7b3c-7456-9abc-def01234567g",
		"bad_variant":      "0198f0a2-7b3c-7456-0abc-def012345678",
		"zero":             "00000000-0000-0000-0000-000000000000",
		"trailing_garbage": testPropertyOptionV7A + "x",
	}
	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			// Given: 비정상 텍스트
			// When: 파싱하면
			_, err := ParsePropertyOptionID(text)
			// Then: typed 오류로 실패 닫기한다.
			if err == nil {
				t.Fatalf("ParsePropertyOptionID(%q) must fail", text)
			}
			if !errors.Is(err, ErrInvalidPropertyOptionIDText) && !errors.Is(err, ErrInvalidPropertyOptionID) {
				t.Fatalf("unexpected error for %q: %v", text, err)
			}
		})
	}
}

func TestPropertyOptionIDRejectsWrongVersion(t *testing.T) {
	// Given: UUIDv5(Registry 유도) 텍스트
	// When: 파싱하면
	_, err := ParsePropertyOptionID(testPropertyOptionV5)
	// Then: 버전 불일치 typed 오류로 실패 닫기한다. option은 항상 Voyager 발급 UUIDv7이다.
	if !errors.Is(err, ErrPropertyOptionIDVersionMismatch) {
		t.Fatalf("want ErrPropertyOptionIDVersionMismatch, got %v", err)
	}
}

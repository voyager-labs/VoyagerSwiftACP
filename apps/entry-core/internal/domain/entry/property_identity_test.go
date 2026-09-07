package entry

import (
	"errors"
	"testing"
)

func TestRegistryPropertyID(t *testing.T) {
	// 고정된 Registry 네임스페이스와 정확한 UUIDv5 리터럴 검증 (ADR-015, 데이터 모델 §5.1).
	if RegistryPropertyNamespace.String() != "4e25d517-09e2-5cbb-83f9-ed2290161e08" {
		t.Fatalf("registry namespace = %s", RegistryPropertyNamespace.String())
	}
	extension, err := RegistryPropertyID("filesystem.extension")
	if err != nil {
		t.Fatal(err)
	}
	if extension.String() != "4b919efd-84e6-5754-a5aa-eb2bef549acc" {
		t.Fatalf("filesystem.extension = %s", extension.String())
	}
	if extension.version() != 5 {
		t.Fatalf("filesystem.extension version = %d", extension.version())
	}
	nameFull, err := RegistryPropertyID("filesystem.name_full")
	if err != nil {
		t.Fatal(err)
	}
	if nameFull.String() != "c4c22664-e220-5d2d-b345-165fbe20305c" {
		t.Fatalf("filesystem.name_full = %s", nameFull.String())
	}
}

func TestRegistryPropertyIDOrderAndMetadataIndependence(t *testing.T) {
	// JSON 순서·Registry 버전·label 변경과 무관하게 동일 key는 동일 ID를 생성한다.
	first, err := RegistryPropertyID("filesystem.extension")
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < 5; index++ {
		again, againErr := RegistryPropertyID("filesystem.extension")
		if againErr != nil {
			t.Fatal(againErr)
		}
		if again != first {
			t.Fatalf("iteration %d produced different id: %s vs %s", index, again, first)
		}
	}
	other, err := RegistryPropertyID("filesystem.name_full")
	if err != nil {
		t.Fatal(err)
	}
	if other == first {
		t.Fatal("different keys produced the same id")
	}
	if _, err := RegistryPropertyID(""); !errors.Is(err, ErrInvalidRegistryPropertyKey) {
		t.Fatalf("empty key error = %v", err)
	}
}

func TestPropertyIdentityScheme(t *testing.T) {
	registryDerived := PropertyIdentitySchemeRegistryDerived
	if !registryDerived.acceptsVersion(5) || registryDerived.acceptsVersion(7) {
		t.Fatal("registry_derived must accept only UUIDv5")
	}
	voyagerIssued := PropertyIdentitySchemeVoyagerIssued
	if !voyagerIssued.acceptsVersion(7) || voyagerIssued.acceptsVersion(5) {
		t.Fatal("voyager_issued must accept only UUIDv7")
	}
	if PropertyIdentityScheme("missing").valid() {
		t.Fatal("unknown scheme must be invalid")
	}
	if !registryDerived.valid() || !voyagerIssued.valid() {
		t.Fatal("known schemes must be valid")
	}
}

func TestPropertyIdentitySchemeRejectsWrongVersion(t *testing.T) {
	// registry_derived는 UUIDv5만, voyager_issued는 UUIDv7만 허용한다.
	registryID := MustPropertyID("4b919efd-84e6-5754-a5aa-eb2bef549acc") // v5
	voyagerID := mustVoyagerPropertyID(t)                                // v7

	if !PropertyIdentitySchemeRegistryDerived.acceptsVersion(registryID.version()) {
		t.Fatal("registry_derived must accept v5")
	}
	if PropertyIdentitySchemeRegistryDerived.acceptsVersion(voyagerID.version()) {
		t.Fatal("registry_derived must reject v7")
	}
	if !PropertyIdentitySchemeVoyagerIssued.acceptsVersion(voyagerID.version()) {
		t.Fatal("voyager_issued must accept v7")
	}
	if PropertyIdentitySchemeVoyagerIssued.acceptsVersion(registryID.version()) {
		t.Fatal("voyager_issued must reject v5")
	}

	// wrong-scheme PropertyDefinition은 Validate에서 거부된다.
	definition := validTextDefinition()
	definition.PropertyID = voyagerID
	definition.IdentityScheme = PropertyIdentitySchemeRegistryDerived
	if _, err := NewPropertyDefinition(definition); !errors.Is(err, ErrInvalidPropertyDefinition) {
		t.Fatalf("registry_derived accepted v7 id: %v", err)
	}
	definition.IdentityScheme = PropertyIdentitySchemeVoyagerIssued
	if _, err := NewPropertyDefinition(definition); err != nil {
		t.Fatalf("voyager_issued rejected v7 id: %v", err)
	}
	definition.PropertyID = registryID
	if _, err := NewPropertyDefinition(definition); !errors.Is(err, ErrInvalidPropertyDefinition) {
		t.Fatalf("voyager_issued accepted v5 id: %v", err)
	}
}

func TestParsePropertyIDCanonical(t *testing.T) {
	id, err := ParsePropertyID("4b919efd-84e6-5754-a5aa-eb2bef549acc")
	if err != nil {
		t.Fatal(err)
	}
	if id.String() != "4b919efd-84e6-5754-a5aa-eb2bef549acc" {
		t.Fatalf("roundtrip = %s", id.String())
	}
	if len(id.Bytes()) != 16 {
		t.Fatalf("bytes length = %d", len(id.Bytes()))
	}
	for _, invalid := range []string{
		"",
		"4B919EFD-84E6-5754-A5AA-EB2BEF549ACC",  // 대문자
		"4b919efd84e65754a5aaeb2bef549acc",      // 하이픈 없음
		"4b919efd-84e6-5754-a5aa-eb2bef549ac",   // 길이 부족
		"4b919efd-84e6-5754-a5aa-eb2bef549acc0", // 길이 초과
		"g4b919efd-84e6-5754-a5aa-eb2bef549acc", // 16진수 아님
	} {
		if _, err := ParsePropertyID(invalid); !errors.Is(err, ErrInvalidPropertyIDText) {
			t.Fatalf("ParsePropertyID(%q) error = %v", invalid, err)
		}
	}
}

func mustVoyagerPropertyID(t *testing.T) PropertyID {
	t.Helper()
	ws, err := NewWorkspaceID()
	if err != nil {
		t.Fatal(err)
	}
	var id PropertyID
	copy(id[:], ws[:])
	return id
}

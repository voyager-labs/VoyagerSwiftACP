// Package propertycatalog는 System Property Registry와 Property Condition
// Registry를 immutable SQL seed와 compiled Go condition catalog로 투영하는
// development/CI-only generator이다. daemon/runtime package가 import하지 않으며,
// runtime은 internal/persistence/sqlite/seeds와
// internal/domain/entry/property_condition_catalog_gen.go의 커밋된 생성 출력만
// 소비한다.
package propertycatalog

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
)

// SystemPropertyRegistry는 raw System Property Registry 문서이다. JSON object
// key 순서는 의도적으로 신뢰하지 않는다. 모든 descriptor는 정확한 (category, key)로
// 키가 정해지고 canonical sort로 처리되어 JSON 재정렬이 생성 출력을 바꾸지 않는다.
type SystemPropertyRegistry struct {
	Version    string
	Categories map[string]map[string]SystemDescriptor
}

// SystemDescriptor는 단일 System Registry descriptor이다.
type SystemDescriptor struct {
	Availability  string
	Description   string
	SearchAliases []string
	SystemKeys    []string
	Type          string
	UILabel       string
	LegacyKeys    []string
	DBIndexed     bool
	UIHidden      bool
	UIPinned      bool
	UnitSpec      *UnitSpec
}

// UnitConversion은 unit_spec.units 배열의 단일 변환 항목이다.
type UnitConversion struct {
	Code              string
	Label             string
	FactorToCanonical string
}

// UnitSpec은 descriptor의 reviewed unit metadata를 담는다.
type UnitSpec struct {
	CanonicalUnit      string
	DefaultDisplayUnit string
	Units              []UnitConversion
}

// rawSystemRegistry는 디코딩용 on-disk JSON layout을 그대로 반영한다.
type rawSystemRegistry struct {
	Kind       string                                    `json:"$kind"`
	Version    string                                    `json:"$version"`
	Categories map[string]map[string]rawSystemDescriptor `json:"categories"`
}

type rawSystemDescriptor struct {
	Availability  *string      `json:"availability"`
	Description   string       `json:"description"`
	SearchAliases []string     `json:"search_aliases"`
	SystemKeys    []string     `json:"system_keys"`
	Type          string       `json:"type"`
	UILabel       string       `json:"ui_label"`
	LegacyKeys    []string     `json:"legacy_keys"`
	DBIndexed     *bool        `json:"db_indexed"`
	UIHidden      *bool        `json:"ui_hidden"`
	UIPinned      *bool        `json:"ui_pinned"`
	UnitSpec      *rawUnitSpec `json:"unit_spec"`
}

type rawUnitSpec struct {
	CanonicalUnit      string              `json:"canonical_unit"`
	DefaultDisplayUnit string              `json:"default_display_unit"`
	Units              []rawUnitConversion `json:"units"`
}

type rawUnitConversion struct {
	Code              string `json:"code"`
	Label             string `json:"label"`
	FactorToCanonical string `json:"factor_to_canonical"`
}

// LoadSystemRegistry는 path에서 System Property Registry를 읽고 디코드한다.
func LoadSystemRegistry(path string) (*SystemPropertyRegistry, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read system registry: %w", err)
	}
	return parseSystemRegistry(raw)
}

// parseSystemRegistry는 System Registry bytes를 디코드하고 검증한다. 테스트가
// inline fixture를 주입할 수 있도록 LoadSystemRegistry와 분리했다.
func parseSystemRegistry(data []byte) (*SystemPropertyRegistry, error) {
	var raw rawSystemRegistry
	if err := decodeJSONDocument(data, &raw); err != nil {
		return nil, fmt.Errorf("decode system registry: %w", err)
	}
	if raw.Kind != "system_property_registry" {
		return nil, errors.New("system registry $kind mismatch")
	}
	if raw.Version == "" {
		return nil, errors.New("system registry missing $version")
	}
	registry := &SystemPropertyRegistry{
		Version:    raw.Version,
		Categories: make(map[string]map[string]SystemDescriptor, len(raw.Categories)),
	}
	for category, descriptors := range raw.Categories {
		converted := make(map[string]SystemDescriptor, len(descriptors))
		for key, descriptor := range descriptors {
			var unit *UnitSpec
			if descriptor.UnitSpec != nil {
				units := make([]UnitConversion, 0, len(descriptor.UnitSpec.Units))
				for _, raw := range descriptor.UnitSpec.Units {
					units = append(units, UnitConversion{
						Code: raw.Code, Label: raw.Label, FactorToCanonical: raw.FactorToCanonical,
					})
				}
				unit = &UnitSpec{
					CanonicalUnit:      descriptor.UnitSpec.CanonicalUnit,
					DefaultDisplayUnit: descriptor.UnitSpec.DefaultDisplayUnit,
					Units:              units,
				}
			}
			converted[key] = SystemDescriptor{
				Availability:  valueOr(descriptor.Availability, ""),
				Description:   descriptor.Description,
				SearchAliases: append([]string(nil), descriptor.SearchAliases...),
				SystemKeys:    append([]string(nil), descriptor.SystemKeys...),
				Type:          descriptor.Type,
				UILabel:       descriptor.UILabel,
				LegacyKeys:    append([]string(nil), descriptor.LegacyKeys...),
				DBIndexed:     valueOr(descriptor.DBIndexed, false),
				UIHidden:      valueOr(descriptor.UIHidden, false),
				UIPinned:      valueOr(descriptor.UIPinned, false),
				UnitSpec:      unit,
			}
		}
		registry.Categories[category] = converted
	}
	if err := registry.Validate(); err != nil {
		return nil, err
	}
	return registry, nil
}

func decodeJSONDocument[T any](data []byte, value *T) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(value); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		if err == nil {
			return errors.New("unexpected trailing JSON value")
		}
		return fmt.Errorf("decode trailing JSON: %w", err)
	}
	return nil
}

// Validate는 Registry 불변식을 검사한다: 정확한 여섯 native type, 비어 있지 않은
// identity 입력, 비어 있지 않은 system_keys, 그리고 단일 descriptor 내 중복
// system key 없음. 동일한 natural source ref는 여러 property에 나타날 수 있다
// (mditem:kMDItemFSName은 설계상 세 property로 매핑). 따라서 cross-property 재사용은
// 허용되고, ambiguous duplicate는 한 descriptor가 key를 반복할 때만 존재한다.
func (registry *SystemPropertyRegistry) Validate() error {
	if registry == nil || registry.Version == "" || len(registry.Categories) == 0 {
		return errors.New("invalid system registry")
	}
	for category, descriptors := range registry.Categories {
		if category == "" {
			return errors.New("empty registry category")
		}
		for key, descriptor := range descriptors {
			if key == "" {
				return fmt.Errorf("empty descriptor key in category %q", category)
			}
			if descriptor.UILabel == "" || descriptor.Type == "" {
				return fmt.Errorf("descriptor %s.%s missing ui_label or type", category, key)
			}
			if !validNativeType(descriptor.Type) {
				return fmt.Errorf("descriptor %s.%s has unknown native type %q", category, key, descriptor.Type)
			}
			if len(descriptor.SystemKeys) == 0 {
				return fmt.Errorf("descriptor %s.%s has no system_keys", category, key)
			}
			seen := make(map[string]struct{}, len(descriptor.SystemKeys))
			for _, systemKey := range descriptor.SystemKeys {
				provider, suffix, ok := splitSystemKey(systemKey)
				if !ok {
					return fmt.Errorf("descriptor %s.%s has malformed system key %q", category, key, systemKey)
				}
				if _, exists := seen[provider+"\x00"+suffix]; exists {
					return fmt.Errorf("descriptor %s.%s repeats system key %q", category, key, systemKey)
				}
				seen[provider+"\x00"+suffix] = struct{}{}
			}
		}
	}
	return nil
}

// CategoriesSorted는 결정적 정렬 순서의 category 이름을 반환한다.
func (registry *SystemPropertyRegistry) CategoriesSorted() []string {
	categories := make([]string, 0, len(registry.Categories))
	for category := range registry.Categories {
		categories = append(categories, category)
	}
	sort.Strings(categories)
	return categories
}

// KeysSorted는 category 내 descriptor key를 결정적 정렬 순서로 반환한다.
func (registry *SystemPropertyRegistry) KeysSorted(category string) []string {
	descriptors := registry.Categories[category]
	keys := make([]string, 0, len(descriptors))
	for key := range descriptors {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

// validNativeType은 value가 여섯 Registry native type 중 하나인지 보고한다.
func validNativeType(value string) bool {
	switch value {
	case "string", "number", "boolean", "date", "string_list", "categorical":
		return true
	default:
		return false
	}
}

// splitSystemKey는 "provider:key"를 (providerPrefix, suffix)로 나눈다. provider
// prefix는 첫 콜론 앞까지이고, suffix는 나머지다.
func splitSystemKey(systemKey string) (provider, suffix string, ok bool) {
	for index := 0; index < len(systemKey); index++ {
		if systemKey[index] == ':' {
			provider = systemKey[:index]
			suffix = systemKey[index+1:]
			return provider, suffix, provider != "" && suffix != ""
		}
	}
	return "", "", false
}

func valueOr[T any](value *T, fallback T) T {
	if value == nil {
		return fallback
	}
	return *value
}

func sortStrings(values []string) {
	sort.Strings(values)
}

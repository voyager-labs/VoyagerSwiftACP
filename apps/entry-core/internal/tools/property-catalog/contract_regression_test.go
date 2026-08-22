package propertycatalog

import (
	"testing"

	entry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

func TestProjectedTagNamesDescriptorsPreserveSelectManyContract(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	for _, nativeKey := range []string{"mditem:kMDItemUserTags", "nsurl:NSURLTagNamesKey"} {
		var found bool
		for _, descriptor := range projection.Snapshot.Descriptors {
			if descriptor.NativeKey != nativeKey {
				continue
			}
			found = true
			if descriptor.NativeType != "string_list" || descriptor.NativeCardinality != entry.PropertyCardinalityMany {
				t.Fatalf("descriptor %q = type %q cardinality %q, want string_list/many", nativeKey, descriptor.NativeType, descriptor.NativeCardinality)
			}
		}
		if !found {
			t.Fatalf("descriptor %q not projected", nativeKey)
		}
	}

	for _, definition := range projection.Snapshot.Definitions {
		if definition.CanonicalKey == "misc.tag_names" {
			if definition.ValueType != entry.PropertyTypeSelect || definition.Cardinality != entry.PropertyCardinalityMany {
				t.Fatalf("misc.tag_names definition = type %q cardinality %q, want select/many", definition.ValueType, definition.Cardinality)
			}
			return
		}
	}
	t.Fatal("misc.tag_names definition not projected")
}

func TestProjectedBindingOrdinalsFollowSystemKeyOrder(t *testing.T) {
	projection, err := ProjectSystemRegistry(loadSystemRegistry(t))
	if err != nil {
		t.Fatalf("project: %v", err)
	}
	registry := loadSystemRegistry(t)
	for category, keys := range registry.Categories {
		for key, descriptor := range keys {
			if len(descriptor.SystemKeys) < 2 {
				continue
			}
			propertyID, err := entry.RegistryPropertyID(category + "." + key)
			if err != nil {
				t.Fatal(err)
			}
			ordinals := make(map[string]int)
			for _, binding := range projection.Snapshot.Bindings {
				if binding.PropertyID == propertyID {
					ordinals[binding.SourceRef.ExternalPropertyID] = binding.BindingOrdinal
				}
			}
			for ordinal, systemKey := range descriptor.SystemKeys {
				_, suffix, ok := splitSystemKey(systemKey)
				if !ok || ordinals[suffix] != ordinal {
					t.Fatalf("%s.%s binding %q ordinal = %d, want %d", category, key, suffix, ordinals[suffix], ordinal)
				}
			}
			return
		}
	}
	t.Fatal("registry has no multi-system-key property")
}

package mount

import (
	"errors"
	"strings"
	"testing"

	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

const (
	localSourceID    = "src:8kHitBFXUPx-VG4Qf_M3LXM1kDu4jXaGZ1JTw9cUiyY"
	externalSourceID = "src:m-KQdBGV6oTOo0uNavbxU6UH9heJBwQTseDcv_utLsE"
)

func TestVirtualPathNormalization(t *testing.T) {
	for _, test := range []struct {
		name string
		raw  string
		want string
	}{
		{name: "root", raw: "/", want: "/"},
		{name: "repeated and trailing slashes", raw: "//team///docs/", want: "/team/docs"},
		{name: "case preserved", raw: "/A", want: "/A"},
		{name: "unicode preserved", raw: "/팀/문서", want: "/팀/문서"},
		{name: "percent sequence preserved", raw: "/a%2Fb", want: "/a%2Fb"},
		{name: "percent encoded dot preserved", raw: "/%2e/%2E%2E", want: "/%2e/%2E%2E"},
	} {
		t.Run(test.name, func(t *testing.T) {
			got, err := NormalizeVirtualPath(test.raw)
			if err != nil {
				t.Fatalf("NormalizeVirtualPath(%q) error = %v", test.raw, err)
			}
			if got.String() != test.want {
				t.Fatalf("NormalizeVirtualPath(%q) = %q, want %q", test.raw, got.String(), test.want)
			}
			if err := got.Validate(); err != nil {
				t.Fatalf("normalized path Validate() error = %v", err)
			}
		})
	}

	for _, test := range []struct {
		name string
		raw  string
	}{
		{name: "empty", raw: ""},
		{name: "relative", raw: "team/docs"},
		{name: "dot segment", raw: "/a/./b"},
		{name: "dot dot segment", raw: "/a/../b"},
		{name: "dot before repeated slash", raw: "/a/.//b"},
		{name: "nul", raw: "/a\x00b"},
		{name: "backslash", raw: "/a\\b"},
		{name: "invalid utf8", raw: string([]byte{'/', 0xff})},
		{name: "raw oversized", raw: strings.Repeat("/", 4097)},
		{name: "normalized oversized", raw: "/" + strings.Repeat("x", 4096)},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := NormalizeVirtualPath(test.raw); !errors.Is(err, ErrInvalidPath) {
				t.Fatalf("NormalizeVirtualPath(%q) error = %v, want %v", test.raw, err, ErrInvalidPath)
			}
		})
	}
}

func TestLongestPrefix(t *testing.T) {
	registry := mustRegistry(t, []Mount{
		{ID: "root", Source: mustSource(t, localSourceID), VirtualPrefix: "/"},
		{ID: "team", Source: mustSource(t, externalSourceID), VirtualPrefix: "/team"},
		{ID: "docs", Source: mustSource(t, localSourceID), VirtualPrefix: "/team/docs"},
	})

	for _, test := range []struct {
		raw          string
		wantMountID  string
		wantSourceID string
		wantRelative string
	}{
		{raw: "/", wantMountID: "root", wantSourceID: localSourceID, wantRelative: ""},
		{raw: "/other", wantMountID: "root", wantSourceID: localSourceID, wantRelative: "other"},
		{raw: "/team", wantMountID: "team", wantSourceID: externalSourceID, wantRelative: ""},
		{raw: "/team/notes", wantMountID: "team", wantSourceID: externalSourceID, wantRelative: "notes"},
		{raw: "//team//docs///readme/", wantMountID: "docs", wantSourceID: localSourceID, wantRelative: "readme"},
	} {
		t.Run(test.raw, func(t *testing.T) {
			got, err := registry.Resolve(test.raw)
			if err != nil {
				t.Fatalf("Resolve(%q) error = %v", test.raw, err)
			}
			if got.MountID != test.wantMountID || got.Source.SourceID != test.wantSourceID || got.RelativePath != test.wantRelative {
				t.Fatalf("Resolve(%q) = %#v", test.raw, got)
			}
			if err := got.Source.Validate(); err != nil {
				t.Fatalf("resolved source Validate() error = %v", err)
			}
		})
	}
}

func TestSegmentBoundary(t *testing.T) {
	withRoot := mustRegistry(t, []Mount{
		{ID: "root", Source: mustSource(t, localSourceID), VirtualPrefix: "/"},
		{ID: "team", Source: mustSource(t, externalSourceID), VirtualPrefix: "/team"},
	})
	got, err := withRoot.Resolve("/teamwork")
	if err != nil {
		t.Fatalf("Resolve() error = %v", err)
	}
	if got.MountID != "root" || got.RelativePath != "teamwork" {
		t.Fatalf("Resolve(/teamwork) = %#v", got)
	}

	withoutRoot := mustRegistry(t, []Mount{{ID: "team", Source: mustSource(t, externalSourceID), VirtualPrefix: "/team"}})
	if _, err := withoutRoot.Resolve("/teamwork"); !errors.Is(err, ErrMountNotFound) {
		t.Fatalf("Resolve(/teamwork) error = %v, want %v", err, ErrMountNotFound)
	}
}

func TestReverseRoundTrip(t *testing.T) {
	registry := mustRegistry(t, []Mount{
		{ID: "root", Source: mustSource(t, localSourceID), VirtualPrefix: "/"},
		{ID: "team", Source: mustSource(t, externalSourceID), VirtualPrefix: "//team/"},
		{ID: "docs", Source: mustSource(t, localSourceID), VirtualPrefix: "/team/docs"},
	})

	for _, raw := range []string{"/", "///", "/other/", "//team/", "/team//notes/", "/team/docs", "//team///docs/readme/", "/a%2Fb"} {
		t.Run(raw, func(t *testing.T) {
			normalized, err := NormalizeVirtualPath(raw)
			if err != nil {
				t.Fatal(err)
			}
			resolved, err := registry.Resolve(raw)
			if err != nil {
				t.Fatal(err)
			}
			reversed, err := registry.Reverse(resolved.MountID, resolved.RelativePath)
			if err != nil {
				t.Fatal(err)
			}
			if reversed.String() != normalized.String() {
				t.Fatalf("Reverse(Resolve(%q)) = %q, want %q", raw, reversed.String(), normalized.String())
			}
		})
	}

	for _, relative := range []string{"/absolute", ".", "..", "../escape", "a/../b", "a/./b", "a//b", "a/", "a\\b", "a\x00b", string([]byte{0xff}), strings.Repeat("x", 4097)} {
		t.Run("reject "+relative, func(t *testing.T) {
			if _, err := registry.Reverse("team", relative); !errors.Is(err, ErrInvalidPath) {
				t.Fatalf("Reverse(%q) error = %v, want %v", relative, err, ErrInvalidPath)
			}
		})
	}
	if _, err := registry.Reverse("", "docs"); !errors.Is(err, ErrMountNotFound) {
		t.Fatalf("Reverse(empty mount) error = %v, want %v", err, ErrMountNotFound)
	}
	if _, err := registry.Reverse("missing", "docs"); !errors.Is(err, ErrMountNotFound) {
		t.Fatalf("Reverse(unknown mount) error = %v, want %v", err, ErrMountNotFound)
	}
	root, err := registry.Reverse("root", "docs")
	if err != nil || root.String() != "/docs" {
		t.Fatalf("root Reverse() = %q, error = %v", root.String(), err)
	}

	maximumPrefix := "/" + strings.Repeat("p", 4095)
	longRegistry := mustRegistry(t, []Mount{{ID: "long", Source: mustSource(t, localSourceID), VirtualPrefix: maximumPrefix}})
	if _, err := longRegistry.Reverse("long", "x"); !errors.Is(err, ErrInvalidPath) {
		t.Fatalf("Reverse() combined oversized path error = %v, want %v", err, ErrInvalidPath)
	}
}

func TestDuplicateMountRejection(t *testing.T) {
	local := mustSource(t, localSourceID)
	external := mustSource(t, externalSourceID)
	for _, test := range []struct {
		name    string
		mounts  []Mount
		wantErr error
	}{
		{name: "duplicate id", mounts: []Mount{{ID: "same", Source: local, VirtualPrefix: "/a"}, {ID: "same", Source: external, VirtualPrefix: "/b"}}, wantErr: ErrDuplicateMountID},
		{name: "equal normalized prefix", mounts: []Mount{{ID: "a", Source: local, VirtualPrefix: "//team/"}, {ID: "b", Source: external, VirtualPrefix: "/team"}}, wantErr: ErrDuplicateMountPrefix},
		{name: "empty id", mounts: []Mount{{Source: local, VirtualPrefix: "/"}}, wantErr: ErrInvalidMount},
		{name: "oversized id", mounts: []Mount{{ID: strings.Repeat("x", 129), Source: local, VirtualPrefix: "/"}}, wantErr: ErrInvalidMount},
		{name: "invalid utf8 id", mounts: []Mount{{ID: string([]byte{0xff}), Source: local, VirtualPrefix: "/"}}, wantErr: ErrInvalidMount},
		{name: "invalid prefix", mounts: []Mount{{ID: "bad", Source: local, VirtualPrefix: "/a/../b"}}, wantErr: ErrInvalidPath},
		{name: "invalid source", mounts: []Mount{{ID: "bad", Source: entry.SourceIdentity{}, VirtualPrefix: "/"}}, wantErr: ErrInvalidMount},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := NewRegistry(test.mounts); !errors.Is(err, test.wantErr) {
				t.Fatalf("NewRegistry() error = %v, want %v", err, test.wantErr)
			}
		})
	}

	mounts := []Mount{{ID: "team", Source: local, VirtualPrefix: "/team"}}
	registry := mustRegistry(t, mounts)
	mounts[0].ID = "mutated"
	mounts[0].Source = external
	mounts[0].VirtualPrefix = "/other"
	got, err := registry.Resolve("/team/docs")
	if err != nil {
		t.Fatal(err)
	}
	if got.MountID != "team" || got.Source.SourceID != localSourceID || got.RelativePath != "docs" {
		t.Fatalf("registry aliases constructor input: %#v", got)
	}
}

func FuzzReverseResolveRoundTrip(f *testing.F) {
	registry := mustRegistry(f, []Mount{
		{ID: "root", Source: mustSource(f, localSourceID), VirtualPrefix: "/"},
		{ID: "team", Source: mustSource(f, externalSourceID), VirtualPrefix: "/team"},
	})
	for _, seed := range []string{"/", "//team///docs/", "/teamwork", "/a%2Fb", "/팀/문서", "/a/../b"} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, raw string) {
		normalized, err := NormalizeVirtualPath(raw)
		if err != nil {
			return
		}
		resolved, err := registry.Resolve(raw)
		if err != nil {
			t.Fatalf("accepted path Resolve(%q) error = %v", raw, err)
		}
		reversed, err := registry.Reverse(resolved.MountID, resolved.RelativePath)
		if err != nil {
			t.Fatalf("accepted path Reverse(%q) error = %v", raw, err)
		}
		if reversed.String() != normalized.String() {
			t.Fatalf("Reverse(Resolve(%q)) = %q, want %q", raw, reversed.String(), normalized.String())
		}
	})
}

func FuzzReverseRejectsRelativeEscapes(f *testing.F) {
	registry := mustRegistry(f, []Mount{{ID: "team", Source: mustSource(f, localSourceID), VirtualPrefix: "/team"}})
	for _, seed := range []string{"", "safe", "nested/path", "팀"} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, tail string) {
		escapes := []string{
			"/" + tail,
			"../" + tail,
			"safe/../" + tail,
			"safe/./" + tail,
			"safe//" + tail,
			"safe\\" + tail,
			"safe\x00" + tail,
			string([]byte{0xff}) + tail,
		}
		for _, relativePath := range escapes {
			if _, err := registry.Reverse("team", relativePath); !errors.Is(err, ErrInvalidPath) {
				t.Fatalf("Reverse(%q) error = %v, want %v", relativePath, err, ErrInvalidPath)
			}
		}
	})
}

func mustSource(tb testing.TB, sourceID string) entry.SourceIdentity {
	tb.Helper()
	source, err := entry.NewSourceIdentity(sourceID, entry.IdentityStrengthLocator)
	if err != nil {
		tb.Fatal(err)
	}
	return source
}

func mustRegistry(tb testing.TB, mounts []Mount) *Registry {
	tb.Helper()
	registry, err := NewRegistry(mounts)
	if err != nil {
		tb.Fatal(err)
	}
	return registry
}

func TestMountRegistryContract(t *testing.T) {
	registry := NewMountRegistry()
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	local := mustCanonicalMount(t, "workspace", "z-local", "/local", localSourceID, available)
	external := mustCanonicalMount(t, "workspace", "a-external", "/external", externalSourceID, available)
	if err := registry.Register(local); err != nil {
		t.Fatal(err)
	}
	generation := registry.Generation()
	if err := registry.Register(external); err != nil {
		t.Fatal(err)
	}
	if registry.Generation() <= generation {
		t.Fatal("generation did not advance")
	}
	listed := registry.ListMounts("workspace")
	if len(listed) != 2 || listed[0].MountID != "a-external" || listed[1].MountID != "z-local" {
		t.Fatalf("mount order = %#v", listed)
	}
	listed[0].MountID = "mutated"
	if registry.ListMounts("workspace")[0].MountID != "a-external" {
		t.Fatal("ListMounts aliases registry state")
	}
	resolved, relative, err := registry.ResolveVirtualPath("workspace", "/external/folder/item")
	if err != nil || resolved.MountID != "a-external" || relative != "folder/item" {
		t.Fatalf("ResolveVirtualPath = %#v %q %v", resolved, relative, err)
	}
	if err := registry.Unmount("a-external"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := registry.ResolveVirtualPath("workspace", "/external/item"); !errors.Is(err, ErrMountNotFound) {
		t.Fatalf("unmounted resolve error = %v", err)
	}
}

func mustCanonicalMount(t *testing.T, workspace, mountID, point, sourceID string, availability entry.Availability) entry.MountRef {
	t.Helper()
	path, err := entry.NewResolvedVirtualPath(mountID, point, "seed")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := entry.NewMountRef(mountID, workspace, sourceID, path, availability, entry.CachePolicyNone)
	if err != nil {
		t.Fatal(err)
	}
	return ref
}

func TestMountRegistryLegacyAndCanonicalShareState(t *testing.T) {
	legacy, err := NewRegistry([]Mount{{ID: "legacy", Source: entry.SourceIdentity{SourceID: localSourceID, IdentityStrength: entry.IdentityStrengthLocator}, VirtualPrefix: "/same"}})
	if err != nil {
		t.Fatal(err)
	}
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	candidate := mustCanonicalMount(t, "legacy", "canonical", "/same", externalSourceID, available)
	if err := legacy.Register(candidate); !errors.Is(err, ErrDuplicateMountPrefix) {
		t.Fatalf("mixed duplicate prefix error = %v", err)
	}
	listed := legacy.ListMounts("legacy")
	if len(listed) != 1 || listed[0].MountID != "legacy" {
		t.Fatalf("legacy canonical list = %#v", listed)
	}
}

func TestMountRegistrySnapshot(t *testing.T) {
	registry := NewMountRegistry()
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	first := mustCanonicalMount(t, "workspace", "first", "/first", localSourceID, available)
	if err := registry.Register(first); err != nil {
		t.Fatal(err)
	}
	snapshot := registry.Snapshot()
	if snapshot.Generation() != registry.Generation() {
		t.Fatalf("generation = %d", snapshot.Generation())
	}
	listed := snapshot.ListMounts("workspace")
	if len(listed) != 1 || listed[0].MountID != "first" {
		t.Fatalf("mounts = %#v", listed)
	}
	listed[0].MountID = "mutated"
	if snapshot.ListMounts("workspace")[0].MountID != "first" {
		t.Fatal("snapshot aliases returned mounts")
	}
	resolved, relative, err := snapshot.ResolveVirtualPath("workspace", "/first/item")
	if err != nil || resolved.MountID != "first" || relative != "item" {
		t.Fatalf("resolve = %#v %q %v", resolved, relative, err)
	}
	reversed, err := snapshot.ReverseVirtualPath("first", "item")
	if err != nil || reversed.String() != "/first/item" {
		t.Fatalf("reverse = %q %v", reversed.String(), err)
	}
}

func TestSnapshotMutationInterleaving(t *testing.T) {
	registry := NewMountRegistry()
	available, _ := entry.NewAvailability(entry.AvailabilityStateAvailable)
	first := mustCanonicalMount(t, "workspace", "first", "/first", localSourceID, available)
	second := mustCanonicalMount(t, "workspace", "second", "/second", externalSourceID, available)
	if err := registry.Register(first); err != nil {
		t.Fatal(err)
	}
	before := registry.Snapshot()
	if err := registry.Register(second); err != nil {
		t.Fatal(err)
	}
	if err := registry.Unmount("first"); err != nil {
		t.Fatal(err)
	}
	if len(before.ListMounts("workspace")) != 1 {
		t.Fatalf("old snapshot changed: %#v", before.ListMounts("workspace"))
	}
	if _, _, err := before.ResolveVirtualPath("workspace", "/first/item"); err != nil {
		t.Fatalf("old snapshot resolve: %v", err)
	}
	after := registry.Snapshot()
	if after.Generation() <= before.Generation() || len(after.ListMounts("workspace")) != 1 || after.ListMounts("workspace")[0].MountID != "second" {
		t.Fatalf("new snapshot = %#v", after.ListMounts("workspace"))
	}
}

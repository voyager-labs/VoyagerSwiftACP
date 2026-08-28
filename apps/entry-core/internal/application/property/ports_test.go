package property

import (
	"context"
	"errors"
	"testing"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

// 컴파일 시점 계약 적합성: 모든 port fake가 계약을 만족해야 한다.
var (
	_ DefinitionRepository  = fakeDefinitionRepository{}
	_ AssignmentRepository  = fakeAssignmentRepository{}
	_ TransactionRunner     = fakeTransactionRunner{}
	_ PropertyOverlayReader = fakeOverlayReader{}
	_ LocalPathResolver     = fakeLocalPathResolver{}
)

type fakeDefinitionRepository struct{}

func (fakeDefinitionRepository) ListDefinitions(_ context.Context, workspace domainentry.WorkspaceContext) ([]domainentry.PropertyDefinition, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	return []domainentry.PropertyDefinition{}, nil
}

func (fakeDefinitionRepository) Definition(_ context.Context, workspace domainentry.WorkspaceContext, _ domainentry.PropertyID) (domainentry.PropertyDefinition, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return domainentry.PropertyDefinition{}, err
	}
	return domainentry.PropertyDefinition{}, nil
}

type fakeAssignmentRepository struct{}

func (fakeAssignmentRepository) AssignmentRevision(_ context.Context, workspace domainentry.WorkspaceContext, _ string, _ domainentry.PropertyID) (uint64, bool, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return 0, false, err
	}
	return 0, false, nil
}

type fakeTransactionRunner struct{}

func (fakeTransactionRunner) WithinTx(_ context.Context, fn func(context.Context) error) error {
	return fn(context.Background())
}

type fakeOverlayReader struct{}

func (fakeOverlayReader) LoadOverlay(_ context.Context, workspace domainentry.WorkspaceContext, _ []string, _ []domainentry.PropertyID) (map[string][]domainentry.PropertyValue, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	return map[string][]domainentry.PropertyValue{}, nil
}

type fakeLocalPathResolver struct{}

func (fakeLocalPathResolver) ResolveLocalPath(_ context.Context, _ string) (ResolvedTarget, error) {
	return ResolvedTarget{}, errors.New("not implemented")
}

// TestPropertyPortRepositoriesRequireInjectedWorkspace는 모든 저장소 호출이
// 데몬이 주입한 Workspace context를 요구하는지 증명한다.
func TestPropertyPortRepositoriesRequireInjectedWorkspace(t *testing.T) {
	var (
		definitions   fakeDefinitionRepository
		assignments   fakeAssignmentRepository
		overlay       fakeOverlayReader
		zeroWorkspace = domainentry.WorkspaceContext{}
	)

	if _, err := definitions.ListDefinitions(context.Background(), zeroWorkspace); !errors.Is(err, ErrWorkspaceRequired) {
		t.Fatalf("ListDefinitions zero workspace error = %v, want %v", err, ErrWorkspaceRequired)
	}
	if _, err := definitions.Definition(context.Background(), zeroWorkspace, domainentry.PropertyID{}); !errors.Is(err, ErrWorkspaceRequired) {
		t.Fatalf("Definition zero workspace error = %v, want %v", err, ErrWorkspaceRequired)
	}
	if _, _, err := assignments.AssignmentRevision(context.Background(), zeroWorkspace, "ent:x", domainentry.PropertyID{}); !errors.Is(err, ErrWorkspaceRequired) {
		t.Fatalf("AssignmentRevision zero workspace error = %v, want %v", err, ErrWorkspaceRequired)
	}
	if _, err := overlay.LoadOverlay(context.Background(), zeroWorkspace, nil, nil); !errors.Is(err, ErrWorkspaceRequired) {
		t.Fatalf("LoadOverlay zero workspace error = %v, want %v", err, ErrWorkspaceRequired)
	}
}

// TestValidateWorkspaceContextAcceptsOnlyTypedIdentity는 영 ID는 거절하고
// 파싱된 UUIDv7 identity만 허용하는지 증명한다.
func TestValidateWorkspaceContextAcceptsOnlyTypedIdentity(t *testing.T) {
	if err := ValidateWorkspaceContext(domainentry.WorkspaceContext{}); !errors.Is(err, ErrWorkspaceRequired) {
		t.Fatalf("zero workspace error = %v, want %v", err, ErrWorkspaceRequired)
	}
	id, err := domainentry.NewWorkspaceID()
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidateWorkspaceContext(domainentry.WorkspaceContext{ID: id}); err != nil {
		t.Fatalf("valid workspace error = %v", err)
	}
}

// mustResolvedTargetFixture는 테스트에서 유효한 ResolvedTarget을 만든다.
func mustResolvedTargetFixture(t *testing.T) ResolvedTarget {
	t.Helper()
	sourceIdentity, err := source.DeriveSourceIdentity("localfs", "/fixture", domainentry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	locator, err := source.NewCanonicalSourceLocator(make([]byte, 32), "localfs", sourceIdentity.SourceID, []byte("/fixture/notes.txt"))
	if err != nil {
		t.Fatal(err)
	}
	locatorRef, err := locator.LocatorRef()
	if err != nil {
		t.Fatal(err)
	}
	entryID := domainentry.DeriveEntryID(sourceIdentity.SourceID, "file", "notes.txt")
	ref, err := domainentry.NewEntryRef(entryID, sourceIdentity.SourceID, "notes.txt", "file", locatorRef, domainentry.IdentityStrengthLocator)
	if err != nil {
		t.Fatal(err)
	}
	return ResolvedTarget{EntryRef: ref, Classification: TargetClassificationLocatorDerived}
}

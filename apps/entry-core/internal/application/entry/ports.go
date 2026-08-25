package entry

import (
	"context"
	"errors"
	"time"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
)

var (
	ErrInvalidRequest               = errors.New("invalid request")
	ErrInvalidSelector              = errors.New("invalid selector")
	ErrInvalidPageToken             = errors.New("invalid page token")
	ErrContextMismatch              = errors.New("context mismatch")
	ErrScopeTooLarge                = errors.New("scope too large")
	ErrPermissionDenied             = errors.New("permission denied")
	ErrEntryNotFound                = errors.New("entry not found")
	ErrApplicationSourceUnavailable = errors.New("source unavailable")
	ErrApplicationSourceDeleted     = errors.New("source deleted")
	ErrApplicationAdapterFailure    = errors.New("adapter failure")
	// ErrAmbiguousSourceBinding와 ErrNoExecutableSourceBinding는 소스 바인딩 선택
	// 계약의 실패 닫기 센티넬이다. 카탈로그에 바인딩이 있는데 실행 가능한 후보가
	// 없거나 동순위 후보가 둘 이상이면 어댑터 호출 없이 요청을 거절한다.
	ErrAmbiguousSourceBinding    = errors.New("ambiguous source binding")
	ErrNoExecutableSourceBinding = errors.New("no executable source binding")
	// ErrPropertyOverlayFailed는 Property overlay 로드·검증·병합이 실패해 요청
	// 전체를 실패 닫기할 때 거절하는 센티널이다. 소스 결과는 부분 노출되지 않는다.
	ErrPropertyOverlayFailed = errors.New("property overlay failed")
)

type ResourceAdapter interface {
	List(context.Context, source.AdapterListRequest) (source.AdapterListResult, error)
	Resolve(context.Context, source.AdapterResolveRequest) (source.AdapterResolveResult, error)
}

type MountRegistry interface {
	Register(domainentry.MountRef) error
	Unmount(mountID string) error
	Snapshot() mount.MountRegistrySnapshot
}

// PropertyOverlayLoader는 Entry 읽기에 끼워 넣는 batched Property overlay 로드
// 계약이다. property 패키지의 PropertyOverlayReader와 의미가 구조적으로 동일하며,
// import 순환을 피하기 위해 entry 자신의 좁은 포트로 선언한다. N+1 조회를 금지하기
// 위해 페이지·배치당 정확히 한 번 호출된다.
type PropertyOverlayLoader interface {
	LoadOverlay(ctx context.Context, workspace domainentry.WorkspaceContext, entryIDs []string, propertyIDs []domainentry.PropertyID) (map[string][]domainentry.PropertyValue, error)
}

type EntryResolver interface {
	SourceObjectToEntryRef(domainentry.SourceRef, source.SourceObjectIdentity) (domainentry.EntryRef, error)
	EntryRefToSourceObject(domainentry.EntryRef) (source.SourceObjectSelector, error)
	VirtualPathToEntryRef(context.Context, string, string, []string) (domainentry.EntryRef, error)
	EntryRefToVirtualPaths(domainentry.EntryRef) ([]domainentry.AccessContext, error)
}

type ResourceAdapterBinding struct {
	SourceRef domainentry.SourceRef
	Adapter   ResourceAdapter
}

type UnifiedListRequest struct {
	WorkspaceID         string
	MountID             *string
	SourceInstanceID    *string
	VirtualPath         *string
	ParentRef           *domainentry.EntryRef
	PageSize            int
	PageToken           *string
	RequestedProperties []string
}

type CanonicalEntry struct {
	EntryRef      domainentry.EntryRef
	EntrySnapshot domainentry.EntrySnapshot
	AccessContext domainentry.AccessContext
}

type RevisionSummary struct {
	SourceInstanceID string
	MountID          string
	SourceRevision   domainentry.Revision
	ObservedRevision domainentry.ObservedRevision
}

type SourceAvailability struct {
	SourceInstanceID string
	MountID          string
	State            domainentry.AvailabilityState
	Error            *ScopeError
}

type SourceFreshness struct {
	SourceInstanceID string
	MountID          string
	State            domainentry.FreshnessState
	ObservedAt       time.Time
	SourceRevision   domainentry.Revision
	LastSyncAt       *time.Time
	StaleAfter       *time.Time
}

type ScopeError struct {
	SourceInstanceID string
	MountID          string
	Code             source.SourceErrorCode
	Message          string
	Retryable        bool
}

type ScopeWarning struct {
	SourceInstanceID string
	MountID          string
	Code             source.WarningCode
	Message          string
	Retryable        bool
}

type UnifiedListResult struct {
	Entries           []CanonicalEntry
	NextPageToken     *string
	HasMore           bool
	ObservedAt        time.Time
	RevisionSummaries []RevisionSummary
	Availabilities    []SourceAvailability
	Freshness         []SourceFreshness
	Warnings          []ScopeWarning
}

type ResolveRequest struct {
	WorkspaceID         string
	EntryRef            *domainentry.EntryRef
	VirtualPath         *string
	MountID             *string
	RequestedProperties []string
}

type ResolveResult struct {
	EntryRef       domainentry.EntryRef
	EntrySnapshot  domainentry.EntrySnapshot
	AccessContext  domainentry.AccessContext
	Capabilities   domainentry.Capabilities
	Availability   domainentry.Availability
	Freshness      domainentry.Freshness
	SourceRevision domainentry.Revision
}

type applicationError struct {
	code    string
	message string
	cause   error
}

func (err *applicationError) Error() string { return err.message }
func (err *applicationError) Unwrap() error { return err.cause }
func (err *applicationError) Code() string  { return err.code }

func newApplicationError(code, message string, cause error) error {
	return &applicationError{code: code, message: message, cause: cause}
}

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

package runtime

// Property application·domain·source 오류와 안정 프로토콜 코드 사상이다.

import (
	"errors"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/mount"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// protocolCodeForPropertyError는 Property application·domain·source 오류를 안정
// 프로토콜 코드로 사상한다. 모든 메시지는 프로토콜 고정 문구로 대체되어 원문이
// 유출되지 않으며, 미지 오류는 internal_error로 실패 닫기된다.
func protocolCodeForPropertyError(err error) schema.ErrorCode {
	switch {
	case errors.Is(err, applicationproperty.ErrStaleDefinitionRevision),
		errors.Is(err, applicationproperty.ErrStaleAssignmentRevision),
		errors.Is(err, applicationproperty.ErrDuplicateDefinitionKey),
		errors.Is(err, applicationproperty.ErrDefinitionInactive),
		errors.Is(err, applicationproperty.ErrOptionInactive),
		errors.Is(err, applicationproperty.ErrDuplicateOptionID),
		errors.Is(err, domainentry.ErrAssignmentInactiveOption):
		return schema.ErrorConflict
	case errors.Is(err, applicationproperty.ErrScopeTooLarge):
		return schema.ErrorScopeTooLarge
	case errors.Is(err, applicationproperty.ErrDefinitionNotFound),
		errors.Is(err, applicationproperty.ErrOptionNotFound):
		return schema.ErrorPropertyNotFound
	case errors.Is(err, applicationproperty.ErrDefinitionNotEditable),
		errors.Is(err, applicationproperty.ErrRegistryOwnedDefinition),
		errors.Is(err, applicationproperty.ErrDefinitionNotSelectable):
		return schema.ErrorUnsupported
	case isPropertyClientContractError(err):
		return schema.ErrorInvalidRequest
	case errors.Is(err, mount.ErrInvalidPath), errors.Is(err, source.ErrPathEscape):
		return schema.ErrorInvalidPath
	case errors.Is(err, source.ErrEntryNotFound):
		return schema.ErrorEntryNotFound
	case errors.Is(err, source.ErrPermissionDenied):
		return schema.ErrorPermissionDenied
	case errors.Is(err, source.ErrSourceUnavailable):
		return schema.ErrorSourceUnavailable
	case errors.Is(err, source.ErrAdapterFailure):
		return schema.ErrorAdapterFailure
	default:
		return schema.ErrorInternal
	}
}

// isPropertyClientContractError는 요청 내용이 정의 계약을 위반한 클라이언트
// 오류군이다. 저장소 이상과 구별해 invalid_request로 사상한다.
func isPropertyClientContractError(err error) bool {
	switch {
	case errors.Is(err, applicationproperty.ErrInvalidChangeRequest),
		errors.Is(err, applicationproperty.ErrDuplicateChangeTarget),
		errors.Is(err, applicationproperty.ErrInvalidOptionOwner),
		errors.Is(err, applicationproperty.ErrInvalidOptionOrder),
		errors.Is(err, applicationproperty.ErrImmutableDefinitionField),
		errors.Is(err, domainentry.ErrInvalidPropertyOptionSet),
		errors.Is(err, domainentry.ErrInvalidEntryPropertyAssignment),
		errors.Is(err, domainentry.ErrInvalidAssignmentTargetKind),
		errors.Is(err, domainentry.ErrInvalidAssignmentState),
		errors.Is(err, domainentry.ErrAssignmentRevisionRequired),
		errors.Is(err, domainentry.ErrAssignmentNullNotAllowed),
		errors.Is(err, domainentry.ErrAssignmentPayloadNotAllowed),
		errors.Is(err, domainentry.ErrAssignmentPayloadRequired),
		errors.Is(err, domainentry.ErrAssignmentValueTypeMismatch),
		errors.Is(err, domainentry.ErrAssignmentCardinalityMismatch),
		errors.Is(err, domainentry.ErrAssignmentDuplicateOrdinal),
		errors.Is(err, domainentry.ErrAssignmentDuplicateOption),
		errors.Is(err, domainentry.ErrAssignmentEmptyScalar),
		errors.Is(err, domainentry.ErrInvalidAssignmentScalar),
		errors.Is(err, domainentry.ErrInvalidAssignmentContract),
		errors.Is(err, domainentry.ErrUnsupportedPropertyType):
		return true
	default:
		return false
	}
}

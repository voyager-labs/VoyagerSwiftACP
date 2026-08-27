package property

import (
	"context"
	"unicode/utf8"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// userDefinitionNamespace는 사용자 생성 정의가 속하는 워크스페이스 내
// namespace다. 시드 시스템 정의의 "system"과 분리된다.
const userDefinitionNamespace = "user"

// CatalogService는 워크스페이스 범위 정의 목록·생성·메타데이터 갱신·비활성화와
// 선택지 create/rename/recolor/reorder/disable 유스케이스를 소유한다. 모든
// mutation은 하나의 TransactionRunner 트랜잭션 안에서 수행되고 성공 시 소유
// 정의의 definition_revision을 정확히 1 올린다. 물리 삭제 경로는 없다.
type CatalogService struct {
	store  CatalogRepository
	runner TransactionRunner
}

// NewCatalogService는 저장소와 트랜잭션 경계를 주입받아 서비스를 만든다.
func NewCatalogService(store CatalogRepository, runner TransactionRunner) (*CatalogService, error) {
	if store == nil || runner == nil {
		return nil, ErrInvalidCatalogService
	}
	return &CatalogService{store: store, runner: runner}, nil
}

// CreateDefinitionInput은 정의 생성 요청이다. ID·namespace·기본값은 서비스가
// 발급하므로 요청은 사용자가 고르는 필드만 운반한다. RequestID는 커밋 전 응답
// 봉투 예산 검사에 쓰이는 echo ID다.
type CreateDefinitionInput struct {
	Key          string
	DisplayName  string
	ValueType    domainentry.PropertyType
	Cardinality  domainentry.PropertyCardinality
	OptionLabels []string
	RequestID    string
}

// newIssuedPropertyID와 newIssuedOptionID는 도메인의 UUIDv7 발급기를
// 재사용한다. WorkspaceID·PropertyID·PropertyOptionID는 같은 RFC 9562
// 레이아웃의 typed [16]byte라 변환이 안전하고 scheme 검사는 도메인 Validate가
// 담당한다.
func newIssuedPropertyID() (domainentry.PropertyID, error) {
	id, err := domainentry.NewWorkspaceID()
	return domainentry.PropertyID(id), err
}

func newIssuedOptionID() (domainentry.PropertyOptionID, error) {
	id, err := domainentry.NewWorkspaceID()
	return domainentry.PropertyOptionID(id), err
}

// CreateDefinition은 ID 발급, domain 검증, namespace/key 유일성, 선택지
// 검증을 하나의 트랜잭션으로 처리한다. 첫 durable 상태의 revision은 1이다.
func (service *CatalogService) CreateDefinition(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	input CreateDefinitionInput,
) (DefinitionView, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return DefinitionView{}, err
	}
	if !utf8.ValidString(input.RequestID) || len(input.RequestID) == 0 || len(input.RequestID) > maximumEchoIDBytes {
		return DefinitionView{}, ErrInvalidChangeRequest
	}
	propertyID, err := newIssuedPropertyID()
	if err != nil {
		return DefinitionView{}, err
	}
	definition := domainentry.WorkspacePropertyDefinition{
		PropertyID:     propertyID,
		Origin:         domainentry.PropertyOriginUserDefined,
		IdentityScheme: domainentry.PropertyIdentitySchemeVoyagerIssued,
		Namespace:      userDefinitionNamespace,
		CanonicalKey:   input.Key,
		DisplayName:    input.DisplayName,
		ValueType:      input.ValueType,
		Cardinality:    input.Cardinality,
		Nullable:       true,
		Editable:       true,
		DefinitionRev:  1,
		Provenance:     domainentry.PropertyProvenanceUserDefined,
		Lifecycle:      domainentry.PropertyLifecycleActive,
	}
	options, err := buildCreatedOptions(definition, input.OptionLabels)
	if err != nil {
		return DefinitionView{}, err
	}
	if err := definition.Validate(); err != nil {
		return DefinitionView{}, err
	}

	var result DefinitionView
	if err := service.runner.WithinTx(ctx, func(txCtx context.Context) error {
		existing, err := service.store.Definitions(txCtx, workspace)
		if err != nil {
			return err
		}
		for _, candidate := range existing {
			if candidate.Namespace == definition.Namespace && candidate.CanonicalKey == definition.CanonicalKey {
				return ErrDuplicateDefinitionKey
			}
		}
		// 커밋 전 응답 봉투 예산 검사다. 요청이 봉투에 들어도 발급 UUID와 상태
		// 필드가 추가된 성공 응답은 초과할 수 있으므로, 초과 예상은 쓰기 없이
		// scope_too_large로 실패 닫기한다(execute의 사전 검사와 같은 계약).
		if !encodedDefinitionResponseFits(input.RequestID, DefinitionView{Definition: definition, Options: options}) {
			return ErrScopeTooLarge
		}
		if err := service.store.PutDefinition(txCtx, definition); err != nil {
			return err
		}
		for _, option := range options {
			if err := service.store.PutOption(txCtx, option); err != nil {
				return err
			}
		}
		result = DefinitionView{Definition: definition, Options: options}
		return nil
	}); err != nil {
		return DefinitionView{}, err
	}
	return result, nil
}

// buildCreatedOptions는 생성 요청의 선택지 라벨을 검증된 선택지 집합으로
// 만든다. select는 최소 하나의 선택지를 요구하고 비선택 유형은 선택지를
// 거절한다.
func buildCreatedOptions(
	definition domainentry.WorkspacePropertyDefinition,
	labels []string,
) ([]domainentry.PropertyOption, error) {
	isSelect := definition.ValueType == domainentry.PropertyTypeSelect
	if !isSelect && len(labels) > 0 {
		return nil, domainentry.ErrInvalidPropertyOptionSet
	}
	if isSelect && len(labels) < 1 {
		return nil, domainentry.ErrInvalidPropertyOptionSet
	}
	if !isSelect {
		return nil, nil
	}
	options := make([]domainentry.PropertyOption, 0, len(labels))
	for ordinal, label := range labels {
		optionID, err := newIssuedOptionID()
		if err != nil {
			return nil, err
		}
		option, err := domainentry.NewPropertyOption(domainentry.PropertyOption{
			OptionID:   optionID,
			PropertyID: definition.PropertyID,
			Label:      label,
			Ordinal:    ordinal,
			Active:     true,
		})
		if err != nil {
			return nil, err
		}
		options = append(options, option)
	}
	if err := domainentry.ValidatePropertyOptions(options); err != nil {
		return nil, err
	}
	return options, nil
}

// ListDefinitions은 비활성 정의를 포함한 전체 목록을 돌려준다. 손실 대신
// 명시적 필터링이 계약이다.
func (service *CatalogService) ListDefinitions(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
) ([]DefinitionView, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, err
	}
	definitions, err := service.store.Definitions(ctx, workspace)
	if err != nil {
		return nil, err
	}
	views := make([]DefinitionView, 0, len(definitions))
	for _, definition := range definitions {
		options, err := service.store.Options(ctx, workspace, definition.PropertyID)
		if err != nil {
			return nil, err
		}
		views = append(views, DefinitionView{Definition: definition, Options: options})
	}
	return views, nil
}

// ListDefinitionsPage는 definition.list의 페이징 유스케이스다. 필터·정렬·창
// 잘라내기를 저장소 쿼리로 밀어 넣고, 반환된 페이지 정의의 선택지만 batched로
// 읽는다. next는 다음 페이지의 after 커서다(has_more일 때만 유효).
func (service *CatalogService) ListDefinitionsPage(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	activeOnly bool,
	idFilter []domainentry.PropertyID,
	after *domainentry.PropertyID,
	limit int,
) ([]DefinitionView, *domainentry.PropertyID, bool, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return nil, nil, false, err
	}
	definitions, next, hasMore, err := service.store.DefinitionsPage(ctx, workspace, activeOnly, idFilter, after, limit)
	if err != nil {
		return nil, nil, false, err
	}
	propertyIDs := make([]domainentry.PropertyID, 0, len(definitions))
	for _, definition := range definitions {
		propertyIDs = append(propertyIDs, definition.PropertyID)
	}
	optionsByProperty, err := service.store.OptionsForDefinitions(ctx, workspace, propertyIDs)
	if err != nil {
		return nil, nil, false, err
	}
	views := make([]DefinitionView, 0, len(definitions))
	for _, definition := range definitions {
		views = append(views, DefinitionView{Definition: definition, Options: optionsByProperty[definition.PropertyID]})
	}
	return views, next, hasMore, nil
}

// Definition은 정의 하나와 그 선택지를 돌려준다. 비활성 행도 과거 assignment
// 해석을 위해 그대로 읽힌다.
func (service *CatalogService) Definition(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
) (DefinitionView, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return DefinitionView{}, err
	}
	definition, err := service.store.Definition(ctx, workspace, propertyID)
	if err != nil {
		return DefinitionView{}, err
	}
	options, err := service.store.Options(ctx, workspace, propertyID)
	if err != nil {
		return DefinitionView{}, err
	}
	return DefinitionView{Definition: definition, Options: options}, nil
}

// definitionByKey는 (namespace, key)로 정의를 찾는 내부 조회다.
func (service *CatalogService) definitionByKey(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	namespace string,
	key string,
) (DefinitionView, error) {
	definitions, err := service.ListDefinitions(ctx, workspace)
	if err != nil {
		return DefinitionView{}, err
	}
	for _, view := range definitions {
		if view.Definition.Namespace == namespace && view.Definition.CanonicalKey == key {
			return view, nil
		}
	}
	return DefinitionView{}, ErrDefinitionNotFound
}

// applyDefinitionUpdate는 갱신 요청이 불변 필드(PropertyID, identity scheme,
// namespace, key, type, cardinality)를 건드리지 않았는지 검사하고 복사본을
// 돌려준다. 표시 이름만 바뀌는 rename-only 요청이 유일한 통과 경로다.
func applyDefinitionUpdate(
	current domainentry.WorkspacePropertyDefinition,
	requested domainentry.WorkspacePropertyDefinition,
) (domainentry.WorkspacePropertyDefinition, error) {
	immutable := requested.PropertyID == current.PropertyID &&
		requested.IdentityScheme == current.IdentityScheme &&
		requested.Namespace == current.Namespace &&
		requested.CanonicalKey == current.CanonicalKey &&
		requested.ValueType == current.ValueType &&
		requested.Cardinality == current.Cardinality &&
		requested.Origin == current.Origin &&
		requested.Provenance == current.Provenance
	if !immutable {
		return domainentry.WorkspacePropertyDefinition{}, ErrImmutableDefinitionField
	}
	updated := requested
	updated.DefinitionRev = current.DefinitionRev
	updated.Lifecycle = current.Lifecycle
	return updated, nil
}

// UpdateDefinitionMetadata는 표시 이름만 갱신한다. CAS 예상 revision 검사,
// 활성 상태 요구, 불변 필드 보존, revision +1이 한 트랜잭션에서 함께 적용된다.
func (service *CatalogService) UpdateDefinitionMetadata(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	requestID string,
	displayName string,
) (DefinitionView, error) {
	return service.mutateDefinition(ctx, workspace, propertyID, expectedRevision, requestID, func(_ context.Context, record *domainentry.WorkspacePropertyDefinition) error {
		requested := *record
		requested.DisplayName = displayName
		updated, err := applyDefinitionUpdate(*record, requested)
		if err != nil {
			return err
		}
		*record = updated
		return nil
	})
}

// DisableDefinition은 정의를 tombstoned로 바꾼다. 행과 선택지 행은 그대로
// 남아 과거 assignment read-back을 보존하고, 이미 비활성인 대상은 거절한다.
// 재활성화 경로는 존재하지 않는다.
func (service *CatalogService) DisableDefinition(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	requestID string,
) (DefinitionView, error) {
	return service.mutateDefinition(ctx, workspace, propertyID, expectedRevision, requestID, func(_ context.Context, record *domainentry.WorkspacePropertyDefinition) error {
		record.Lifecycle = domainentry.PropertyLifecycleTombstoned
		return nil
	})
}

// mutateDefinition은 모든 정의 mutation의 공통 골격이다. tx 안에서 대상을
// 읽고, 활성 상태와 CAS 예상 revision을 검사한 뒤 mutate를 적용하고,
// revision을 정확히 1 올려 저장한다. 저장 후 결과 뷰(정의+전체 선택지)를
// 기준으로 커밋 전 응답 예산을 다시 검사해 초과 예상은 쓰기 0으로 실패 닫기
// 한다. 봉투 초과 판정에는 응답 echo ID가 필요하므로 요청 ID를 골격까지
// 전달한다.
func (service *CatalogService) mutateDefinition(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	requestID string,
	mutate func(txCtx context.Context, record *domainentry.WorkspacePropertyDefinition) error,
) (DefinitionView, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return DefinitionView{}, err
	}
	// create와 같은 echo ID 검증 계약이다(change.execute도 동일). 유효하지 않은
	// 요청 ID로는 커밋 전 예산 판정 자체가 불가능하므로 tx 밖에서 먼저 거절한다.
	if !utf8.ValidString(requestID) || len(requestID) == 0 || len(requestID) > maximumEchoIDBytes {
		return DefinitionView{}, ErrInvalidChangeRequest
	}
	var result DefinitionView
	if err := service.runner.WithinTx(ctx, func(txCtx context.Context) error {
		current, err := service.store.Definition(txCtx, workspace, propertyID)
		if err != nil {
			return err
		}
		if current.IdentityScheme != domainentry.PropertyIdentitySchemeVoyagerIssued {
			// System Registry 시드(registry_derived) 정의는 사용자 mutation
			// 대상이 아니다. digest나 lifecycle을 바꾸면 다음 시작의 seed
			// 검증이 실패해 daemon이 기동 전에 종료된다.
			return ErrRegistryOwnedDefinition
		}
		if current.Lifecycle != domainentry.PropertyLifecycleActive {
			return ErrDefinitionInactive
		}
		if current.DefinitionRev != expectedRevision {
			return ErrStaleDefinitionRevision
		}
		if err := mutate(txCtx, &current); err != nil {
			return err
		}
		current.DefinitionRev++
		if err := current.Validate(); err != nil {
			return err
		}
		if err := service.store.SaveDefinition(txCtx, current); err != nil {
			return err
		}
		options, err := service.store.Options(txCtx, workspace, propertyID)
		if err != nil {
			return err
		}
		result = DefinitionView{Definition: current, Options: options}
		// tx 안이므로 ErrScopeTooLarge 반환 시 골격 쓰기까지 롤백되어 쓰기 0이
		// 보장된다. 정의·선택지 mutation의 최종 결과 뷰에 대해 검사하는 것은
		// update가 이름/라벨 길이를 키워 응답 크기를 바꿀 수 있기 때문이다.
		if !encodedDefinitionResponseFits(requestID, result) {
			return ErrScopeTooLarge
		}
		return nil
	}); err != nil {
		return DefinitionView{}, err
	}
	return result, nil
}

package property

import (
	"context"

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
// 발급하므로 요청은 사용자가 고르는 필드만 운반한다.
type CreateDefinitionInput struct {
	Key          string
	DisplayName  string
	ValueType    domainentry.PropertyType
	Cardinality  domainentry.PropertyCardinality
	OptionLabels []string
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
	displayName string,
) (DefinitionView, error) {
	return service.mutateDefinition(ctx, workspace, propertyID, expectedRevision, func(_ context.Context, record *domainentry.WorkspacePropertyDefinition) error {
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
) (DefinitionView, error) {
	return service.mutateDefinition(ctx, workspace, propertyID, expectedRevision, func(_ context.Context, record *domainentry.WorkspacePropertyDefinition) error {
		record.Lifecycle = domainentry.PropertyLifecycleTombstoned
		return nil
	})
}

// mutateDefinition은 모든 정의 mutation의 공통 골격이다. tx 안에서 대상을
// 읽고, 활성 상태와 CAS 예상 revision을 검사한 뒤 mutate를 적용하고,
// revision을 정확히 1 올려 저장한다.
func (service *CatalogService) mutateDefinition(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	mutate func(txCtx context.Context, record *domainentry.WorkspacePropertyDefinition) error,
) (DefinitionView, error) {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return DefinitionView{}, err
	}
	var result DefinitionView
	if err := service.runner.WithinTx(ctx, func(txCtx context.Context) error {
		current, err := service.store.Definition(txCtx, workspace, propertyID)
		if err != nil {
			return err
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
		return nil
	}); err != nil {
		return DefinitionView{}, err
	}
	return result, nil
}

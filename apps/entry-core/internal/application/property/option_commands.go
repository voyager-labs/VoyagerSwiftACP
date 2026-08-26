package property

import (
	"context"

	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
)

// CreateOption은 select 정의에 선택지를 추가한다. 새 선택지는 활성 상태로
// 마지막 ordinal 뒤에 붙고 소유 정의의 revision이 1 올라간다.
func (service *CatalogService) CreateOption(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	label string,
) (DefinitionView, error) {
	return service.mutateDefinition(ctx, workspace, propertyID, expectedRevision, func(txCtx context.Context, record *domainentry.WorkspacePropertyDefinition) error {
		if record.ValueType != domainentry.PropertyTypeSelect {
			return ErrDefinitionNotSelectable
		}
		options, err := service.store.Options(ctx, workspace, propertyID)
		if err != nil {
			return err
		}
		optionID, err := newIssuedOptionID()
		if err != nil {
			return err
		}
		option, err := domainentry.NewPropertyOption(domainentry.PropertyOption{
			OptionID:   optionID,
			PropertyID: propertyID,
			Label:      label,
			Ordinal:    len(options),
			Active:     true,
		})
		if err != nil {
			return err
		}
		expanded := append(append([]domainentry.PropertyOption(nil), options...), option)
		if err := domainentry.ValidatePropertyOptions(expanded); err != nil {
			return err
		}
		return service.store.PutOption(ctx, option)
	})
}

// RenameOption은 선택지 label을 바꾼다. Option value는 PropertyOptionID로
// 참조되므로 기존 assignment는 영향을 받지 않는다.
func (service *CatalogService) RenameOption(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	optionID domainentry.PropertyOptionID,
	expectedRevision int,
	label string,
) (DefinitionView, error) {
	if err := service.requireOptionOwnership(ctx, workspace, propertyID, optionID); err != nil {
		return DefinitionView{}, err
	}
	return service.mutateOptions(ctx, workspace, propertyID, expectedRevision, func(_ context.Context, options []domainentry.PropertyOption) ([]domainentry.PropertyOption, error) {
		index, active, err := locateActiveOption(options, optionID)
		if err != nil {
			return nil, err
		}
		if !active {
			return nil, ErrOptionInactive
		}
		options[index].Label = label
		return options, nil
	})
}

// RecolorOption은 선택지 표시 색상을 바꾼다. identity와 순서는 보존된다.
func (service *CatalogService) RecolorOption(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	optionID domainentry.PropertyOptionID,
	expectedRevision int,
	color string,
) (DefinitionView, error) {
	if err := service.requireOptionOwnership(ctx, workspace, propertyID, optionID); err != nil {
		return DefinitionView{}, err
	}
	return service.mutateOptions(ctx, workspace, propertyID, expectedRevision, func(_ context.Context, options []domainentry.PropertyOption) ([]domainentry.PropertyOption, error) {
		index, active, err := locateActiveOption(options, optionID)
		if err != nil {
			return nil, err
		}
		if !active {
			return nil, ErrOptionInactive
		}
		options[index].Color = color
		return options, nil
	})
}

// ReorderOptions는 활성 선택지의 순서를 바꾼다. 요청 순서는 활성 선택지의
// 정확한 순열이어야 하고 비활성 선택지는 현재 ordinal 순서대로 뒤에 이어져
// 전체 집합을 0..n-1로 다시 매긴다. 물리 유일 인덱스 덕에 중복 ordinal은
// 저장소에서도 거절된다.
func (service *CatalogService) ReorderOptions(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	orderedIDs []domainentry.PropertyOptionID,
) (DefinitionView, error) {
	return service.mutateOptions(ctx, workspace, propertyID, expectedRevision, func(_ context.Context, options []domainentry.PropertyOption) ([]domainentry.PropertyOption, error) {
		reordered, err := reorderOptionRows(options, orderedIDs)
		if err != nil {
			return nil, err
		}
		return reordered, nil
	})
}

// DisableOption은 선택지를 비활성화한다. 행은 그대로 남아 과거 assignment
// read-back을 보존하며 이미 비활성인 대상은 거절한다.
func (service *CatalogService) DisableOption(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	optionID domainentry.PropertyOptionID,
	expectedRevision int,
) (DefinitionView, error) {
	if err := service.requireOptionOwnership(ctx, workspace, propertyID, optionID); err != nil {
		return DefinitionView{}, err
	}
	return service.mutateOptions(ctx, workspace, propertyID, expectedRevision, func(_ context.Context, options []domainentry.PropertyOption) ([]domainentry.PropertyOption, error) {
		index, active, err := locateActiveOption(options, optionID)
		if err != nil {
			return nil, err
		}
		if !active {
			return nil, ErrOptionInactive
		}
		options[index].Active = false
		return options, nil
	})
}

// mutateOptions는 선택지 mutation의 공통 골격이다. 정의 골격(mutateDefinition)이
// 활성·CAS·revision 규칙을 집행하고 여기서는 select 유형 요구와 선택지 집합
// 검증을 추가한다.
func (service *CatalogService) mutateOptions(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	expectedRevision int,
	mutate func(txCtx context.Context, options []domainentry.PropertyOption) ([]domainentry.PropertyOption, error),
) (DefinitionView, error) {
	return service.mutateDefinition(ctx, workspace, propertyID, expectedRevision, func(txCtx context.Context, record *domainentry.WorkspacePropertyDefinition) error {
		if record.ValueType != domainentry.PropertyTypeSelect {
			return ErrDefinitionNotSelectable
		}
		options, err := service.store.Options(txCtx, workspace, propertyID)
		if err != nil {
			return err
		}
		updated, err := mutate(txCtx, options)
		if err != nil {
			return err
		}
		if err := domainentry.ValidatePropertyOptions(updated); err != nil {
			return err
		}
		return service.store.SaveOptions(txCtx, updated)
	})
}

// requireOptionOwnership은 대상 선택지가 존재하고 요청한 정의에 속하는지
// 먼저 검사한다. 다른 정의의 선택지는 not-found가 아니라 ownership 오류로
// 거절된다.
func (service *CatalogService) requireOptionOwnership(
	ctx context.Context,
	workspace domainentry.WorkspaceContext,
	propertyID domainentry.PropertyID,
	optionID domainentry.PropertyOptionID,
) error {
	if err := ValidateWorkspaceContext(workspace); err != nil {
		return err
	}
	option, err := service.store.Option(ctx, workspace, optionID)
	if err != nil {
		return err
	}
	if option.PropertyID != propertyID {
		return ErrInvalidOptionOwner
	}
	return nil
}

// locateActiveOption은 스코핑된 선택지 집합에서 대상을 찾는다. 없으면
// ErrOptionNotFound, 비활성이면 ErrOptionInactive다.
func locateActiveOption(
	options []domainentry.PropertyOption,
	optionID domainentry.PropertyOptionID,
) (int, bool, error) {
	for index := range options {
		if options[index].OptionID == optionID {
			return index, options[index].Active, nil
		}
	}
	return 0, false, ErrOptionNotFound
}

// reorderOptionRows는 활성 순열 검사와 재번호 매기기를 수행한다. 요청에 없는
// 활성 선택지, 모르는 ID, 중복 ID는 모두 ErrInvalidOptionOrder다.
func reorderOptionRows(
	options []domainentry.PropertyOption,
	orderedIDs []domainentry.PropertyOptionID,
) ([]domainentry.PropertyOption, error) {
	activeCount := 0
	for _, option := range options {
		if option.Active {
			activeCount++
		}
	}
	if len(orderedIDs) != activeCount {
		return nil, ErrInvalidOptionOrder
	}
	positionByID := make(map[domainentry.PropertyOptionID]int, len(orderedIDs))
	for position, id := range orderedIDs {
		if _, duplicate := positionByID[id]; duplicate {
			return nil, ErrInvalidOptionOrder
		}
		positionByID[id] = position
	}
	reordered := make([]domainentry.PropertyOption, len(options))
	nextOrdinal := 0
	for _, id := range orderedIDs {
		found := false
		for index := range options {
			if options[index].OptionID != id || !options[index].Active {
				continue
			}
			reordered[nextOrdinal] = options[index]
			reordered[nextOrdinal].Ordinal = nextOrdinal
			nextOrdinal++
			found = true
			break
		}
		if !found {
			return nil, ErrInvalidOptionOrder
		}
	}
	for _, option := range options {
		if !option.Active {
			reordered[nextOrdinal] = option
			reordered[nextOrdinal].Ordinal = nextOrdinal
			nextOrdinal++
		}
	}
	return reordered, nil
}

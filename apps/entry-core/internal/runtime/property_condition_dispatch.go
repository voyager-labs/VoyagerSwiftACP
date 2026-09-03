package runtime

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"sort"

	applicationproperty "github.com/voyager-labs/voyager-app/apps/entry-core/internal/application/property"
	domainentry "github.com/voyager-labs/voyager-app/apps/entry-core/internal/domain/entry"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

func dispatchPropertyConditionQuery(ctx context.Context, request schema.Request, workspaceID string, baseService PropertyService, tokenKey [32]byte) schema.Response {
	workspace, ok := propertyDispatchGuard(ctx, workspaceID, baseService)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	service, ok := baseService.(propertyConditionQueryService)
	if !ok {
		return dispatchError(request, schema.ErrorInternal)
	}
	params := request.PropertyConditionQueryParams
	query, code := conditionQueryFromWire(params)
	if code != "" {
		return dispatchError(request, code)
	}
	contextDigest, ok := propertyQueryContextDigest(workspaceID, params)
	if !ok {
		return dispatchError(request, schema.ErrorInvalidRequest)
	}
	if params.PageToken != nil {
		offset, tokenDigest, valid := decodePropertyQueryToken(*params.PageToken, tokenKey)
		if !valid {
			return dispatchError(request, schema.ErrorInvalidPageToken)
		}
		if !hmac.Equal(tokenDigest[:], contextDigest[:]) {
			return dispatchError(request, schema.ErrorContextMismatch)
		}
		if offset < 0 || offset >= len(query.LocalPaths) {
			return dispatchError(request, schema.ErrorInvalidPageToken)
		}
		query.CandidateOffset = offset
	}
	result, err := service.Query(ctx, workspace, query)
	if err != nil {
		return dispatchError(request, protocolCodeForConditionQueryError(err))
	}
	wireItems := make([]schema.PropertyConditionQueryItem, 0, len(result.Items))
	for _, item := range result.Items {
		projection := make([]schema.PropertyAssignment, 0, len(item.Projection))
		for _, fact := range item.Projection {
			mapped, mapCode := assignmentFactToWire(fact, result.Definitions)
			if mapCode != "" {
				return dispatchError(request, mapCode)
			}
			projection = append(projection, mapped)
		}
		sort.Slice(projection, func(i, j int) bool { return projection[i].PropertyID < projection[j].PropertyID })
		wireItems = append(wireItems, schema.PropertyConditionQueryItem{CandidateIndex: item.CandidateIndex, EntryID: item.EntryID, Projection: projection})
	}
	var nextToken *string
	if result.HasMore {
		token := encodePropertyQueryToken(result.NextCandidateOffset, contextDigest, tokenKey)
		nextToken = &token
	}
	wireResult := schema.PropertyConditionQueryResult{Items: wireItems, UnresolvedCandidateIndices: result.UnresolvedCandidateIndices, CatalogVersion: domainentry.ConditionCatalogVersion, NextPageToken: nextToken, HasMore: result.HasMore}
	return dispatchPropertySuccess(request, wireResult)
}

func protocolCodeForConditionQueryError(err error) schema.ErrorCode {
	if errors.Is(err, source.ErrSourceUnavailable) {
		return schema.ErrorSourceRuntimeUnavailable
	}
	return protocolCodeForPropertyError(err)
}

func conditionQueryFromWire(params *schema.PropertyConditionQueryParams) (applicationproperty.ConditionQuery, schema.ErrorCode) {
	if params == nil {
		return applicationproperty.ConditionQuery{}, schema.ErrorInvalidRequest
	}
	query := applicationproperty.ConditionQuery{Combinator: params.Combinator, EvaluationDate: params.EvaluationDate, PageSize: params.PageSize}
	for _, target := range params.Targets {
		query.LocalPaths = append(query.LocalPaths, target.LocalPath)
	}
	ids, err := parsePropertyIDs(params.ProjectionPropertyIDs)
	if err != nil {
		return applicationproperty.ConditionQuery{}, schema.ErrorInvalidRequest
	}
	query.ProjectionPropertyIDs = ids
	for _, condition := range params.Conditions {
		propertyID, err := domainentry.ParsePropertyID(condition.PropertyID)
		if err != nil {
			return applicationproperty.ConditionQuery{}, schema.ErrorInvalidRequest
		}
		operand := applicationproperty.ConditionOperand{Kind: condition.Operand.Kind, Values: append([]string(nil), condition.Operand.Values...)}
		if condition.Operand.Boolean != nil {
			value := *condition.Operand.Boolean
			operand.Boolean = &value
		}
		query.Conditions = append(query.Conditions, applicationproperty.QueryCondition{PropertyID: propertyID, Operator: condition.Operator, Operand: operand})
	}
	return query, ""
}

func propertyQueryContextDigest(workspaceID string, params *schema.PropertyConditionQueryParams) ([32]byte, bool) {
	if params == nil {
		return [32]byte{}, false
	}
	type contextValue struct {
		WorkspaceID           string                          `json:"workspace_id"`
		Targets               []schema.PropertyTargetSelector `json:"targets"`
		Combinator            string                          `json:"combinator"`
		Conditions            []schema.PropertyCondition      `json:"conditions"`
		ProjectionPropertyIDs []string                        `json:"projection_property_ids"`
		EvaluationDate        string                          `json:"evaluation_date"`
		PageSize              int                             `json:"page_size"`
	}
	encoded, err := json.Marshal(contextValue{WorkspaceID: workspaceID, Targets: params.Targets, Combinator: params.Combinator, Conditions: params.Conditions, ProjectionPropertyIDs: params.ProjectionPropertyIDs, EvaluationDate: params.EvaluationDate, PageSize: params.PageSize})
	if err != nil {
		return [32]byte{}, false
	}
	return sha256.Sum256(encoded), true
}

func encodePropertyQueryToken(offset int, contextDigest [32]byte, key [32]byte) string {
	payload := make([]byte, 40)
	binary.BigEndian.PutUint64(payload[:8], uint64(offset))
	copy(payload[8:], contextDigest[:])
	mac := hmac.New(sha256.New, key[:])
	_, _ = mac.Write(payload)
	return base64.RawURLEncoding.EncodeToString(append(payload, mac.Sum(nil)...))
}

func decodePropertyQueryToken(token string, key [32]byte) (int, [32]byte, bool) {
	decoded, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(decoded) != 72 {
		return 0, [32]byte{}, false
	}
	payload, signature := decoded[:40], decoded[40:]
	mac := hmac.New(sha256.New, key[:])
	_, _ = mac.Write(payload)
	if !hmac.Equal(signature, mac.Sum(nil)) {
		return 0, [32]byte{}, false
	}
	offset := binary.BigEndian.Uint64(payload[:8])
	if offset > uint64(^uint(0)>>1) {
		return 0, [32]byte{}, false
	}
	var digest [32]byte
	copy(digest[:], payload[8:])
	return int(offset), digest, true
}

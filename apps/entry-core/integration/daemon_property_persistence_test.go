package integration

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"gorm.io/gorm"

	sqlite "github.com/voyager-labs/voyager-app/apps/entry-core/internal/persistence/sqlite"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/source/localfs"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/testfixture"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

// 이 파일은 VOY-765 todo 11의 real-daemon Property UDS/restart persistence
// 증명이다. 모든 호출은 공개 UDS 와이어 계약만 통과하고(테스트 전용 우회 없음),
// entry_id 오라클은 production localfs adapter를 재사용한다.

const propertyCallTimeout = 2 * time.Second

type propertyPersistenceEnv struct {
	tempRoot   string
	daemonPath string
	socketPath string
}

// --- 공용 헬퍼 ---

func encodePropertyRequest(requestID string, method schema.Method, params map[string]any) []byte {
	wire, err := json.Marshal(map[string]any{"request_id": requestID, "method": method, "params": params})
	if err != nil {
		panic(fmt.Sprintf("encode property request: %v", err))
	}
	return wire
}

func udsExchange(t *testing.T, socketPath string, request []byte, method schema.Method) schema.Response {
	t.Helper()
	connection, err := net.DialTimeout("unix", socketPath, time.Second)
	if err != nil {
		t.Fatalf("dial daemon socket: %v", err)
	}
	defer connection.Close()
	if err := connection.SetDeadline(time.Now().Add(propertyCallTimeout)); err != nil {
		t.Fatalf("bound property call connection: %v", err)
	}
	unixConnection, ok := connection.(*net.UnixConn)
	if !ok {
		t.Fatal("property call connection is not Unix")
	}
	if _, err := connection.Write(request); err != nil {
		t.Fatalf("write property request: %v", err)
	}
	if err := unixConnection.CloseWrite(); err != nil {
		t.Fatalf("half-close property request: %v", err)
	}
	responseWire, err := io.ReadAll(io.LimitReader(connection, schema.MaxWireBytes+1))
	if err != nil {
		t.Fatalf("read property response: %v", err)
	}
	if len(responseWire) > schema.MaxWireBytes {
		t.Fatalf("property response exceeds envelope: %d bytes", len(responseWire))
	}
	response, err := schema.DecodeResponse(responseWire, method)
	if err != nil {
		t.Fatalf("decode property response: %v; wire=%s", err, responseWire)
	}
	return response
}

// udsOversizedExchange는 봉투를 넘는 요청을 보낸다. 서버가 LimitReader 상한까지만
// 읽고 닫기 때문에 쓰기는 별도 고루틴에서 EPIPE를 무시하며 수행해야 한다.
func udsOversizedExchange(t *testing.T, socketPath string, payload []byte) schema.Response {
	t.Helper()
	connection, err := net.DialTimeout("unix", socketPath, time.Second)
	if err != nil {
		t.Fatalf("dial daemon socket for oversized request: %v", err)
	}
	defer connection.Close()
	if err := connection.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		t.Fatalf("bound oversized call connection: %v", err)
	}
	unixConnection, ok := connection.(*net.UnixConn)
	if !ok {
		t.Fatal("oversized call connection is not Unix")
	}
	go func() {
		_, _ = connection.Write(payload)
		_ = unixConnection.CloseWrite()
	}()
	responseWire, err := io.ReadAll(io.LimitReader(connection, schema.MaxWireBytes+1))
	if err != nil {
		t.Fatalf("read oversized response: %v", err)
	}
	if len(responseWire) > schema.MaxWireBytes {
		t.Fatalf("oversized response exceeds envelope: %d bytes", len(responseWire))
	}
	response, err := schema.DecodeResponse(responseWire, schema.MethodPing)
	if err != nil {
		t.Fatalf("decode oversized response: %v; wire=%s", err, responseWire)
	}
	return response
}

func propertyCall(t *testing.T, socketPath, requestID string, method schema.Method, params map[string]any) schema.Response {
	t.Helper()
	return udsExchange(t, socketPath, encodePropertyRequest(requestID, method, params), method)
}

func requireSuccess(t *testing.T, response schema.Response, context string) {
	t.Helper()
	if response.Error != nil {
		t.Fatalf("%s failed: code=%s message=%s", context, response.Error.Code, response.Error.Message)
	}
}

func definitionResult(t *testing.T, response schema.Response, context string) schema.PropertyDefinition {
	t.Helper()
	requireSuccess(t, response, context)
	result, ok := response.Result.(schema.PropertyDefinitionResult)
	if !ok {
		t.Fatalf("%s result type=%T", context, response.Result)
	}
	return result.Definition
}

type definitionIndex map[string]schema.PropertyDefinition

func listAllDefinitions(t *testing.T, socketPath string) definitionIndex {
	t.Helper()
	definitions := definitionIndex{}
	pageToken := (*string)(nil)
	for page := 0; ; page++ {
		if page > 64 {
			t.Fatal("definition paging did not terminate")
		}
		params := map[string]any{"page_size": 32, "requested_property_ids": []string{}, "include_disabled": true}
		if pageToken != nil {
			params["page_token"] = *pageToken
		}
		response := propertyCall(t, socketPath, fmt.Sprintf("def-list-%d", page), schema.MethodPropertyDefinitionList, params)
		requireSuccess(t, response, fmt.Sprintf("definition list page %d", page))
		result, ok := response.Result.(schema.PropertyDefinitionListResult)
		if !ok {
			t.Fatalf("definition list page %d result type=%T", page, response.Result)
		}
		for _, definition := range result.Definitions {
			if _, duplicate := definitions[definition.Key]; duplicate {
				t.Fatalf("duplicate definition key %q across pages", definition.Key)
			}
			definitions[definition.Key] = definition
		}
		if !result.HasMore {
			break
		}
		pageToken = result.NextPageToken
	}
	return definitions
}

func createDefinition(
	t *testing.T,
	socketPath, key, name, valueType, cardinality string,
	optionLabels []string,
) schema.PropertyDefinition {
	t.Helper()
	params := map[string]any{"key": key, "name": name, "value_type": valueType, "cardinality": cardinality}
	if optionLabels != nil {
		options := make([]map[string]string, len(optionLabels))
		for index, label := range optionLabels {
			options[index] = map[string]string{"label": label}
		}
		params["options"] = options
	}
	response := propertyCall(t, socketPath, "def-create-"+key, schema.MethodPropertyDefinitionCreate, params)
	return definitionResult(t, response, "create definition "+key)
}

func renameDefinition(t *testing.T, socketPath, propertyID string, expectedRevision int64, name string) schema.PropertyDefinition {
	t.Helper()
	response := propertyCall(t, socketPath, "def-rename-"+name, schema.MethodPropertyDefinitionUpdate, map[string]any{
		"property_id": propertyID, "expected_definition_revision": expectedRevision, "name": name,
	})
	return definitionResult(t, response, "rename definition to "+name)
}

func reorderOptions(t *testing.T, socketPath, propertyID string, expectedRevision int64, optionIDs []string) schema.PropertyDefinition {
	t.Helper()
	response := propertyCall(t, socketPath, "option-reorder", schema.MethodPropertyOptionReorder, map[string]any{
		"property_id": propertyID, "expected_definition_revision": expectedRevision, "option_ids": optionIDs,
	})
	return definitionResult(t, response, "reorder options")
}

func disableOption(t *testing.T, socketPath, propertyID, optionID string, expectedRevision int64) schema.PropertyDefinition {
	t.Helper()
	response := propertyCall(t, socketPath, "option-disable", schema.MethodPropertyOptionDisable, map[string]any{
		"property_id": propertyID, "option_id": optionID, "expected_definition_revision": expectedRevision,
	})
	return definitionResult(t, response, "disable option "+optionID)
}

func optionByLabel(t *testing.T, definition schema.PropertyDefinition, label string) schema.PropertyOption {
	t.Helper()
	for _, option := range definition.Options {
		if option.Label == label {
			return option
		}
	}
	t.Fatalf("definition %s has no option labeled %q", definition.Key, label)
	return schema.PropertyOption{}
}

func mustTextPayload(t *testing.T, value string) *schema.PropertyPayload {
	t.Helper()
	payload, ok := schema.NewPropertyPayload("text", "one", value, nil)
	if !ok {
		t.Fatalf("build text payload of %d bytes", len(value))
	}
	return &payload
}

func textChangeTarget(t *testing.T, localPath, propertyID string, definitionRevision, assignmentRevision int64, value string) schema.PropertyChangeTarget {
	t.Helper()
	return schema.PropertyChangeTarget{
		Target:                     schema.PropertyTargetSelector{Kind: "local_path", LocalPath: localPath},
		PropertyID:                 propertyID,
		ExpectedDefinitionRevision: definitionRevision,
		ExpectedAssignmentRevision: assignmentRevision,
		Desired:                    schema.PropertyDesiredState{State: "value", ValueType: "text", Cardinality: "one", Payload: mustTextPayload(t, value)},
	}
}

func stateChangeTarget(localPath, propertyID string, definitionRevision, assignmentRevision int64, state string) schema.PropertyChangeTarget {
	return schema.PropertyChangeTarget{
		Target:                     schema.PropertyTargetSelector{Kind: "local_path", LocalPath: localPath},
		PropertyID:                 propertyID,
		ExpectedDefinitionRevision: definitionRevision,
		ExpectedAssignmentRevision: assignmentRevision,
		Desired:                    schema.PropertyDesiredState{State: state},
	}
}

func prepareChanges(t *testing.T, socketPath, requestID string, changes []schema.PropertyChangeTarget) schema.PropertyChangePrepareResult {
	t.Helper()
	response := propertyCall(t, socketPath, requestID, schema.MethodPropertyChangePrepare, map[string]any{"changes": changes})
	requireSuccess(t, response, "prepare "+requestID)
	result, ok := response.Result.(schema.PropertyChangePrepareResult)
	if !ok {
		t.Fatalf("prepare %s result type=%T", requestID, response.Result)
	}
	return result
}

func executeChanges(t *testing.T, socketPath, requestID string, changes []schema.PropertyChangeTarget) []schema.PropertyAssignment {
	t.Helper()
	response := propertyCall(t, socketPath, requestID, schema.MethodPropertyChangeExecute, map[string]any{"changes": changes})
	requireSuccess(t, response, "execute "+requestID)
	result, ok := response.Result.(schema.PropertyChangeExecuteResult)
	if !ok {
		t.Fatalf("execute %s result type=%T", requestID, response.Result)
	}
	return result.Assignments
}

func listAssignments(t *testing.T, socketPath, requestID, localPath string, propertyIDs []string) []schema.PropertyAssignment {
	t.Helper()
	response := propertyCall(t, socketPath, requestID, schema.MethodPropertyAssignmentList, map[string]any{
		"page_size":              256,
		"requested_property_ids": propertyIDs,
		"target":                 map[string]any{"kind": "local_path", "local_path": localPath},
	})
	requireSuccess(t, response, "assignment list "+localPath)
	result, ok := response.Result.(schema.PropertyAssignmentListResult)
	if !ok {
		t.Fatalf("assignment list %s result type=%T", localPath, response.Result)
	}
	if result.HasMore || result.NextPageToken != nil {
		t.Fatalf("assignment list %s unexpectedly paged", localPath)
	}
	return result.Assignments
}

func assertTextValueAssignment(t *testing.T, assignment schema.PropertyAssignment, propertyID, entryID, wantState, wantValue string, wantRevision int64) {
	t.Helper()
	if assignment.PropertyID != propertyID || assignment.EntryID != entryID || assignment.ValueType != "text" ||
		assignment.Cardinality != "one" || assignment.State != wantState || assignment.Revision != wantRevision {
		t.Fatalf("assignment mismatch: got pid=%s entry=%s type=%s card=%s state=%s rev=%d, want state=%s rev=%d",
			assignment.PropertyID, assignment.EntryID, assignment.ValueType, assignment.Cardinality,
			assignment.State, assignment.Revision, wantState, wantRevision)
	}
	switch wantState {
	case "value":
		if assignment.Payload == nil {
			t.Fatalf("assignment payload missing for value row: %+v", assignment)
		}
		text, ok := assignment.Payload.One().(string)
		if !ok || text != wantValue {
			t.Fatalf("assignment payload=%#v, want %q", assignment.Payload.One(), wantValue)
		}
	default:
		if assignment.Payload != nil {
			t.Fatalf("assignment payload present for %s row: %+v", wantState, assignment.Payload)
		}
	}
}

type entryIDOracle struct {
	adapter *localfs.Adapter
}

func newEntryIDOracle(t *testing.T) entryIDOracle {
	t.Helper()
	adapter, err := localfs.New(localfs.Config{
		Root:       "/",
		Generation: "integration-oracle",
		CursorKey:  bytes.Repeat([]byte{0x2A}, 32),
	})
	if err != nil {
		t.Fatal(err)
	}
	return entryIDOracle{adapter: adapter}
}

func (oracle entryIDOracle) entryID(t *testing.T, localPath string) string {
	t.Helper()
	ref, err := oracle.adapter.ResolveLocalPath(context.Background(), localPath)
	if err != nil {
		t.Fatalf("oracle resolve %s: %v", localPath, err)
	}
	return ref.EntryID
}

func copySmokeFixture(t *testing.T, path string) {
	t.Helper()
	testfixture.CopyFile(t, path, testfixture.PlainText)
}

func writeNumberedFiles(t *testing.T, dir string, count int) []string {
	t.Helper()
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatalf("create batch dir: %v", err)
	}
	paths := make([]string, count)
	for index := range count {
		path := filepath.Join(dir, fmt.Sprintf("f%02d", index))
		copySmokeFixture(t, path)
		paths[index] = path
	}
	return paths
}

func stopDaemonCleanly(t *testing.T, daemon *daemonProcess, socketPath string) {
	t.Helper()
	if err := daemon.cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatalf("send SIGTERM to daemon: %v", err)
	}
	if err := daemon.wait(10 * time.Second); err != nil {
		t.Fatalf("daemon did not exit after SIGTERM: %v; stderr=%q", err, daemon.stderr.String())
	}
	if daemon.cmd.ProcessState == nil || !daemon.cmd.ProcessState.Exited() || daemon.cmd.ProcessState.ExitCode() != 0 {
		t.Fatalf("daemon was not reaped with exit 0: state=%v", daemon.cmd.ProcessState)
	}
	if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after daemon exit: %v", err)
	}
}

func runPropertyConditionQuery(t *testing.T, env propertyPersistenceEnv) {
	dbPath := filepath.Join(env.tempRoot, "property-condition-query.db")
	paths := writeNumberedFiles(t, filepath.Join(env.tempRoot, "query"), 2)
	daemon := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)
	definition := createDefinition(t, env.socketPath, "query_text", "Query Text", "text", "one", nil)
	executeChanges(t, env.socketPath, "query-seed", []schema.PropertyChangeTarget{
		textChangeTarget(t, paths[0], definition.PropertyID, definition.Revision, 0, "match"),
		textChangeTarget(t, paths[1], definition.PropertyID, definition.Revision, 0, "match"),
	})
	params := map[string]any{
		"targets":                 []map[string]any{{"kind": "local_path", "local_path": paths[0]}, {"kind": "local_path", "local_path": paths[1]}},
		"combinator":              "all",
		"conditions":              []map[string]any{{"property_id": definition.PropertyID, "operator": "eq", "operand": map[string]any{"kind": "text", "values": []string{"match"}}}},
		"projection_property_ids": []string{definition.PropertyID}, "evaluation_date": "2026-09-01", "page_size": 1,
	}
	page1Response := propertyCall(t, env.socketPath, "query-page-1", schema.MethodPropertyConditionQuery, params)
	requireSuccess(t, page1Response, "condition query page 1")
	page1 := page1Response.Result.(schema.PropertyConditionQueryResult)
	if len(page1.Items) != 1 || page1.Items[0].CandidateIndex != 0 || len(page1.Items[0].Projection) != 1 || !page1.HasMore || page1.NextPageToken == nil {
		t.Fatalf("page 1 = %+v", page1)
	}
	pageParams := cloneQueryParams(params)
	pageParams["page_token"] = *page1.NextPageToken
	page2Response := propertyCall(t, env.socketPath, "query-page-2", schema.MethodPropertyConditionQuery, pageParams)
	requireSuccess(t, page2Response, "condition query page 2")
	page2 := page2Response.Result.(schema.PropertyConditionQueryResult)
	if len(page2.Items) != 1 || page2.Items[0].CandidateIndex != 1 || page2.HasMore {
		t.Fatalf("page 2 = %+v", page2)
	}

	tampered := cloneQueryParams(params)
	tampered["page_token"] = *page1.NextPageToken + "x"
	if response := propertyCall(t, env.socketPath, "query-tamper", schema.MethodPropertyConditionQuery, tampered); response.Error == nil || response.Error.Code != schema.ErrorInvalidPageToken {
		t.Fatalf("tamper error = %+v", response.Error)
	}
	changed := cloneQueryParams(pageParams)
	changed["combinator"] = "any"
	if response := propertyCall(t, env.socketPath, "query-context", schema.MethodPropertyConditionQuery, changed); response.Error == nil || response.Error.Code != schema.ErrorContextMismatch {
		t.Fatalf("context error = %+v", response.Error)
	}

	stopDaemonCleanly(t, daemon, env.socketPath)
	restart := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, restart, env.socketPath, 15*time.Second)
	if response := propertyCall(t, env.socketPath, "query-restart-token", schema.MethodPropertyConditionQuery, pageParams); response.Error == nil || response.Error.Code != schema.ErrorInvalidPageToken {
		t.Fatalf("restart token error = %+v", response.Error)
	}
	repeated := propertyCall(t, env.socketPath, "query-page-1-repeat", schema.MethodPropertyConditionQuery, params)
	requireSuccess(t, repeated, "condition query repeated page 1")
	repeatedPage := repeated.Result.(schema.PropertyConditionQueryResult)
	if len(repeatedPage.Items) != 1 || repeatedPage.Items[0].EntryID != page1.Items[0].EntryID {
		t.Fatalf("repeated page = %+v, original = %+v", repeatedPage, page1)
	}
	stopDaemonCleanly(t, restart, env.socketPath)
}

func cloneQueryParams(source map[string]any) map[string]any {
	cloned := make(map[string]any, len(source)+1)
	for key, value := range source {
		cloned[key] = value
	}
	return cloned
}

// databaseBytesDigest는 db 파일과 WAL 파일의 결합 다이제스트를 돌려준다.
// 거절된 mutation 전후 비교로 롤백을 증명한다(-shm은 읽기 잠금 마커가 변하므로 제외).
func databaseBytesDigest(t *testing.T, dbPath string) [sha256.Size]byte {
	t.Helper()
	digest := sha256.New()
	for _, suffix := range []string{"", "-wal"} {
		data, err := os.ReadFile(dbPath + suffix)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			t.Fatalf("read %s%s: %v", dbPath, suffix, err)
		}
		digest.Write([]byte(suffix))
		digest.Write(data)
	}
	var out [sha256.Size]byte
	copy(out[:], digest.Sum(nil))
	return out
}

// loadAssignmentQueryCounts는 daemon 완전 종료 후 같은 DB를 in-process로 열어
// LoadAssignments의 SQL 질의 수를 GORM 콜백으로 센다. tx 안에서 콜백을 등록하는
// 이유는 Session() 얕은 복사로 파생 인스턴스가 콜백을 공유하기 때문이다.
func loadAssignmentQueryCounts(t *testing.T, dbPath string, batches [][]string) []int {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	store, err := sqlite.Open(ctx, dbPath)
	if err != nil {
		t.Fatalf("open store for query counting: %v", err)
	}
	defer func() { _ = store.Close() }()
	wsctx, err := store.BootstrapOrRestoreWorkspace(ctx)
	if err != nil {
		t.Fatalf("restore workspace for query counting: %v", err)
	}
	facts := sqlite.NewEntryPropertyFactStore(store)
	counts := make([]int, len(batches))
	for index, entryIDs := range batches {
		var queries int64
		callbackName := fmt.Sprintf("integration_query_count_%d", index)
		txErr := store.WithinTx(ctx, func(tx *gorm.DB) error {
			registerErr := tx.Callback().Query().Before("gorm:query").Register(callbackName, func(*gorm.DB) {
				queries++
			})
			if registerErr != nil {
				return registerErr
			}
			_, loadErr := facts.LoadAssignments(store.WithTxScope(ctx, tx), wsctx, entryIDs, nil)
			return loadErr
		})
		if txErr != nil {
			t.Fatalf("counted LoadAssignments (%d entry ids): %v", len(entryIDs), txErr)
		}
		counts[index] = int(queries)
	}
	return counts
}

// --- subtest 1: property_atomic_persistence ---

func runPropertyAtomicPersistence(t *testing.T, env propertyPersistenceEnv) {
	dbPath := filepath.Join(env.tempRoot, "property-atomic.db")
	lifecyclePaths := []string{
		filepath.Join(env.tempRoot, "f00"),
		filepath.Join(env.tempRoot, "f01"),
		filepath.Join(env.tempRoot, "f02"),
	}
	for _, path := range lifecyclePaths {
		copySmokeFixture(t, path)
	}
	batchPaths := writeNumberedFiles(t, filepath.Join(env.tempRoot, "batch"), 32)
	oracle := newEntryIDOracle(t)

	daemon := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)

	definitions := listAllDefinitions(t, env.socketPath)
	status, exists := definitions["status"]
	if !exists || status.ValueType != "select" || status.Cardinality != "one" {
		t.Fatalf("status preset missing or wrong contract: %+v", status)
	}
	priority, exists := definitions["priority"]
	if !exists || priority.ValueType != "select" {
		t.Fatalf("priority preset missing or wrong contract: %+v", priority)
	}

	// 정의 수명주기: create → update(rename) → select create → reorder → disable.
	textDef := createDefinition(t, env.socketPath, "smoke_text", "Smoke Text", "text", "one", nil)
	if textDef.Revision != 1 {
		t.Fatalf("fresh definition revision=%d, want 1", textDef.Revision)
	}
	renamedText := renameDefinition(t, env.socketPath, textDef.PropertyID, textDef.Revision, "Smoke Text v2")
	if renamedText.Revision != textDef.Revision+1 {
		t.Fatalf("renamed revision=%d, want %d", renamedText.Revision, textDef.Revision+1)
	}
	stateDef := createDefinition(t, env.socketPath, "smoke_state", "Smoke State", "select", "one", []string{"Alpha", "Beta"})
	alpha := optionByLabel(t, stateDef, "Alpha")
	beta := optionByLabel(t, stateDef, "Beta")
	if alpha.Position != 0 || beta.Position != 1 {
		t.Fatalf("created option positions alpha=%d beta=%d, want 0 and 1 (decoded domain ordinals)", alpha.Position, beta.Position)
	}
	reordered := reorderOptions(t, env.socketPath, stateDef.PropertyID, stateDef.Revision, []string{beta.OptionID, alpha.OptionID})
	reorderedAlpha := optionByLabel(t, reordered, "Alpha")
	reorderedBeta := optionByLabel(t, reordered, "Beta")
	if reordered.Revision != stateDef.Revision+1 || reorderedBeta.Position != 0 || reorderedAlpha.Position != 1 {
		t.Fatalf("reorder revision/positions: rev=%d alpha=%d beta=%d", reordered.Revision, reorderedAlpha.Position, reorderedBeta.Position)
	}
	optionDisabled := disableOption(t, env.socketPath, stateDef.PropertyID, alpha.OptionID, reordered.Revision)
	disabledAlpha := optionByLabel(t, optionDisabled, "Alpha")
	disabledBeta := optionByLabel(t, optionDisabled, "Beta")
	if optionDisabled.Revision != reordered.Revision+1 || disabledAlpha.State != "disabled" || disabledBeta.State != "active" {
		t.Fatalf("option disable: rev=%d alpha=%s beta=%s", optionDisabled.Revision, disabledAlpha.State, disabledBeta.State)
	}

	// local_path resolve + implicit unset 스냅샷(빈 목록).
	snapshot := listAssignments(t, env.socketPath, "snapshot-f00", lifecyclePaths[0], []string{textDef.PropertyID})
	if len(snapshot) != 0 {
		t.Fatalf("implicit unset snapshot rows=%+v, want empty", snapshot)
	}

	setChanges := make([]schema.PropertyChangeTarget, len(lifecyclePaths))
	for index, path := range lifecyclePaths {
		setChanges[index] = textChangeTarget(t, path, textDef.PropertyID, renamedText.Revision, 0, "v1")
	}
	prepared := prepareChanges(t, env.socketPath, "prep-set", setChanges)
	if !prepared.RequiresConfirmation || len(prepared.Changes) != len(lifecyclePaths) {
		t.Fatalf("prepare confirmation/count: %+v", prepared.RequiresConfirmation)
	}
	for index, change := range prepared.Changes {
		wantEntryID := oracle.entryID(t, lifecyclePaths[index])
		if change.EntryID != wantEntryID || change.Before != nil || change.After.State != "value" {
			t.Fatalf("prepared change %d: entry=%s before=%+v after=%+v", index, change.EntryID, change.Before, change.After)
		}
	}

	setRows := executeChanges(t, env.socketPath, "exec-set", setChanges)
	for index, row := range setRows {
		assertTextValueAssignment(t, row, textDef.PropertyID, oracle.entryID(t, lifecyclePaths[index]), "value", "v1", 1)
	}
	readBack := listAssignments(t, env.socketPath, "list-f01", lifecyclePaths[1], []string{textDef.PropertyID})
	if len(readBack) != 1 {
		t.Fatalf("read-back rows=%d, want 1", len(readBack))
	}
	assertTextValueAssignment(t, readBack[0], textDef.PropertyID, oracle.entryID(t, lifecyclePaths[1]), "value", "v1", 1)

	replaceChanges := make([]schema.PropertyChangeTarget, len(lifecyclePaths))
	for index, path := range lifecyclePaths {
		replaceChanges[index] = textChangeTarget(t, path, textDef.PropertyID, renamedText.Revision, 1, "v2")
	}
	replacePrepared := prepareChanges(t, env.socketPath, "prep-replace", replaceChanges)
	for index, change := range replacePrepared.Changes {
		if change.Before == nil || change.Before.Revision != 1 {
			t.Fatalf("replace prepared before %d: %+v", index, change.Before)
		}
	}
	replaceRows := executeChanges(t, env.socketPath, "exec-replace", replaceChanges)
	for index, row := range replaceRows {
		assertTextValueAssignment(t, row, textDef.PropertyID, oracle.entryID(t, lifecyclePaths[index]), "value", "v2", 2)
	}

	clearChanges := make([]schema.PropertyChangeTarget, len(lifecyclePaths))
	for index, path := range lifecyclePaths {
		clearChanges[index] = stateChangeTarget(path, textDef.PropertyID, renamedText.Revision, 2, "unknown")
	}
	clearRows := executeChanges(t, env.socketPath, "exec-clear", clearChanges)
	for index, row := range clearRows {
		assertTextValueAssignment(t, row, textDef.PropertyID, oracle.entryID(t, lifecyclePaths[index]), "unknown", "", 3)
	}
	cleared := listAssignments(t, env.socketPath, "list-cleared", lifecyclePaths[0], []string{textDef.PropertyID})
	if len(cleared) != 1 {
		t.Fatalf("cleared rows=%d, want durable unset row", len(cleared))
	}
	assertTextValueAssignment(t, cleared[0], textDef.PropertyID, oracle.entryID(t, lifecyclePaths[0]), "unknown", "", 3)

	// stale revision 롤백 증명: 거절 전후 DB+WAL 바이트 동일. 현재 domain
	// revision 3인 f00에 wire revision 1(domain 0)을 예상하면 CAS가 거절한다.
	digestBefore := databaseBytesDigest(t, dbPath)
	staleChanges := []schema.PropertyChangeTarget{textChangeTarget(t, lifecyclePaths[0], textDef.PropertyID, renamedText.Revision, 1, "vX")}
	staleResponse := propertyCall(t, env.socketPath, "exec-stale", schema.MethodPropertyChangeExecute, map[string]any{"changes": staleChanges})
	if staleResponse.Error == nil || staleResponse.Error.Code != schema.ErrorConflict {
		t.Fatalf("stale execute error=%+v, want conflict", staleResponse.Error)
	}
	if digestAfter := databaseBytesDigest(t, dbPath); digestAfter != digestBefore {
		t.Fatal("rejected stale execute changed database bytes")
	}

	// restart 전 사용자 preset 편집: rename Status, disable Backlog, reverse Priority.
	statusRenamed := renameDefinition(t, env.socketPath, status.PropertyID, status.Revision, "Status (edited)")
	backlog := optionByLabel(t, status, "Backlog")
	statusEdited := disableOption(t, env.socketPath, status.PropertyID, backlog.OptionID, statusRenamed.Revision)
	priorityIDs := make([]string, 0, len(priority.Options))
	for index := len(priority.Options) - 1; index >= 0; index-- {
		priorityIDs = append(priorityIDs, priority.Options[index].OptionID)
	}
	priorityReordered := reorderOptions(t, env.socketPath, priority.PropertyID, priority.Revision, priorityIDs)

	stopDaemonCleanly(t, daemon, env.socketPath)

	// 같은 DB로 재시작: 부팅 preset 재조정이 사용자 편집을 덮쓰지 않는지 검증.
	restart := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, restart, env.socketPath, 15*time.Second)
	afterRestart := listAllDefinitions(t, env.socketPath)

	rereadText := afterRestart["smoke_text"]
	if rereadText.Name != "Smoke Text v2" || rereadText.Revision != renamedText.Revision {
		t.Fatalf("smoke_text after restart: name=%q rev=%d", rereadText.Name, rereadText.Revision)
	}
	rereadState := afterRestart["smoke_state"]
	if rereadState.Revision != optionDisabled.Revision {
		t.Fatalf("smoke_state revision after restart=%d, want %d", rereadState.Revision, optionDisabled.Revision)
	}
	rereadAlpha := optionByLabel(t, rereadState, "Alpha")
	rereadBeta := optionByLabel(t, rereadState, "Beta")
	if rereadAlpha.State != "disabled" || rereadAlpha.Position != 1 || rereadBeta.State != "active" || rereadBeta.Position != 0 {
		t.Fatalf("smoke_state options after restart: alpha=%+v beta=%+v", rereadAlpha, rereadBeta)
	}
	rereadStatus := afterRestart["status"]
	if rereadStatus.Name != "Status (edited)" || rereadStatus.Revision != statusEdited.Revision {
		t.Fatalf("status preset user rename overwritten: name=%q rev=%d", rereadStatus.Name, rereadStatus.Revision)
	}
	rereadBacklog := optionByLabel(t, rereadStatus, "Backlog")
	if rereadBacklog.State != "disabled" {
		t.Fatalf("status Backlog re-enabled by preset reconcile: %+v", rereadBacklog)
	}
	if len(rereadStatus.Options) != len(status.Options) {
		t.Fatalf("status option count changed across restart: %d -> %d", len(status.Options), len(rereadStatus.Options))
	}
	rereadPriority := afterRestart["priority"]
	if rereadPriority.Revision != priorityReordered.Revision || len(rereadPriority.Options) != len(priorityIDs) {
		t.Fatalf("priority order not preserved: rev=%d options=%d", rereadPriority.Revision, len(rereadPriority.Options))
	}
	for index, wantID := range priorityIDs {
		if rereadPriority.Options[index].OptionID != wantID {
			t.Fatalf("priority order position %d changed across restart", index)
		}
	}
	for _, path := range lifecyclePaths {
		rows := listAssignments(t, env.socketPath, "reread-"+filepath.Base(path), path, []string{textDef.PropertyID})
		if len(rows) != 1 {
			t.Fatalf("post-restart rows for %s=%d, want 1", path, len(rows))
		}
		assertTextValueAssignment(t, rows[0], textDef.PropertyID, oracle.entryID(t, path), "unknown", "", 3)
	}

	stopDaemonCleanly(t, restart, env.socketPath)

	// 질의 예산 증명: 1개 vs 32개 entry ID의 LoadAssignments 질의 수 동일.
	singleBatch := []string{oracle.entryID(t, batchPaths[0])}
	fullBatch := make([]string, len(batchPaths))
	for index, path := range batchPaths {
		fullBatch[index] = oracle.entryID(t, path)
	}
	counts := loadAssignmentQueryCounts(t, dbPath, [][]string{singleBatch, fullBatch})
	if counts[0] == 0 || counts[0] != counts[1] {
		t.Fatalf("LoadAssignments query counts 1 id=%d 32 ids=%d, want equal non-zero batched reads", counts[0], counts[1])
	}
	t.Logf("LoadAssignments query budget: %d queries for both 1 and 32 entry ids", counts[0])
}

// --- subtest 2: property_response_budget_preflight ---

func runPropertyResponseBudgetPreflight(t *testing.T, env propertyPersistenceEnv) {
	dbPath := filepath.Join(env.tempRoot, "property-budget.db")
	targetPaths := writeNumberedFiles(t, filepath.Join(env.tempRoot, "budget"), 32)
	oracle := newEntryIDOracle(t)

	daemon := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)
	defer stopDaemonCleanly(t, daemon, env.socketPath)

	textDef := createDefinition(t, env.socketPath, "smoke_budget", "Smoke Budget", "text", "one", nil)
	value := strings.Repeat("x", 4096)
	changes := make([]schema.PropertyChangeTarget, len(targetPaths))
	for index, path := range targetPaths {
		changes[index] = textChangeTarget(t, path, textDef.PropertyID, textDef.Revision, 0, value)
	}
	request := encodePropertyRequest("budget-preflight", schema.MethodPropertyChangeExecute, map[string]any{"changes": changes})

	// 요청/응답 크기 관계: 각 change의 4096바이트 값이 양방향에 그대로 실리고
	// 요청만 target selector를 추가로 운반하므로, 요청이 봉투 안에 들어가는
	// 순간 예상 응답도 반드시 봉투 안에 들어간다(행당 요청 오버헤드 > 응답 오버헤드).
	// 따라서 "요청 ≤65,536 AND 예상 응답 >65,536"은 구조적으로 불가능하고,
	// 32×4096 요청은 dispatch 전 request_too_large로 실패 닫기된다.
	if len(request) <= schema.MaxWireBytes {
		t.Fatalf("encoded request=%d bytes, want over the %d-byte envelope for this scenario", len(request), schema.MaxWireBytes)
	}

	projected := make([]schema.PropertyAssignment, len(targetPaths))
	for index, path := range targetPaths {
		projected[index] = schema.PropertyAssignment{
			PropertyID:  textDef.PropertyID,
			EntryID:     oracle.entryID(t, path),
			ValueType:   "text",
			Cardinality: "one",
			State:       "value",
			Revision:    1,
			Payload:     mustTextPayload(t, value),
		}
	}
	projectedBytes, fits := schema.EncodedSuccessBytes("budget-preflight", schema.PropertyChangeExecuteResult{Assignments: projected})
	if projectedBytes <= schema.MaxWireBytes || fits {
		t.Fatalf("projected success encoding=%d bytes fits=%t, want over the envelope", projectedBytes, fits)
	}

	response := udsOversizedExchange(t, env.socketPath, request)
	if response.Error == nil || response.Error.Code != schema.ErrorRequestTooLarge {
		t.Fatalf("oversized execute error=%+v, want request_too_large", response.Error)
	}
	rows := listAssignments(t, env.socketPath, "budget-post-read", targetPaths[0], []string{textDef.PropertyID})
	if len(rows) != 0 {
		t.Fatalf("post-read rows=%+v, want untouched implicit unset snapshot", rows)
	}
}

// --- sibling failure subtests ---

func runPropertyStaleMiddleTarget(t *testing.T, env propertyPersistenceEnv) {
	dbPath := filepath.Join(env.tempRoot, "property-stale-middle.db")
	paths := []string{
		filepath.Join(env.tempRoot, "m0"),
		filepath.Join(env.tempRoot, "m1"),
		filepath.Join(env.tempRoot, "m2"),
	}
	for _, path := range paths {
		copySmokeFixture(t, path)
	}
	daemon := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)
	defer stopDaemonCleanly(t, daemon, env.socketPath)

	textDef := createDefinition(t, env.socketPath, "smoke_stale", "Smoke Stale", "text", "one", nil)
	changes := []schema.PropertyChangeTarget{
		textChangeTarget(t, paths[0], textDef.PropertyID, textDef.Revision, 0, "v1"),
		textChangeTarget(t, paths[1], textDef.PropertyID, textDef.Revision, 1, "v1"),
		textChangeTarget(t, paths[2], textDef.PropertyID, textDef.Revision, 0, "v1"),
	}
	response := propertyCall(t, env.socketPath, "exec-stale-middle", schema.MethodPropertyChangeExecute, map[string]any{"changes": changes})
	if response.Error == nil || response.Error.Code != schema.ErrorConflict {
		t.Fatalf("stale middle error=%+v, want conflict", response.Error)
	}
	for _, path := range paths {
		if rows := listAssignments(t, env.socketPath, "verify-"+filepath.Base(path), path, []string{textDef.PropertyID}); len(rows) != 0 {
			t.Fatalf("target %s mutated by rejected change: %+v", path, rows)
		}
	}
}

func runPropertyInvalidFinalTarget(t *testing.T, env propertyPersistenceEnv) {
	dbPath := filepath.Join(env.tempRoot, "property-invalid-final.db")
	firstPath := filepath.Join(env.tempRoot, "i0")
	copySmokeFixture(t, firstPath)
	missingPath := filepath.Join(env.tempRoot, "missing-target")
	daemon := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)
	defer stopDaemonCleanly(t, daemon, env.socketPath)

	textDef := createDefinition(t, env.socketPath, "smoke_invalid", "Smoke Invalid", "text", "one", nil)
	changes := []schema.PropertyChangeTarget{
		textChangeTarget(t, firstPath, textDef.PropertyID, textDef.Revision, 0, "v1"),
		textChangeTarget(t, missingPath, textDef.PropertyID, textDef.Revision, 0, "v1"),
	}
	response := propertyCall(t, env.socketPath, "exec-invalid-final", schema.MethodPropertyChangeExecute, map[string]any{"changes": changes})
	if response.Error == nil || response.Error.Code != schema.ErrorEntryNotFound {
		t.Fatalf("invalid final target error=%+v, want entry_not_found", response.Error)
	}
	if rows := listAssignments(t, env.socketPath, "verify-i0", firstPath, []string{textDef.PropertyID}); len(rows) != 0 {
		t.Fatalf("earlier target mutated by rejected change: %+v", rows)
	}
}

func runPropertyInaccessiblePath(t *testing.T, env propertyPersistenceEnv) {
	if os.Geteuid() == 0 {
		t.Skip("root bypasses file permission checks")
	}
	dbPath := filepath.Join(env.tempRoot, "property-inaccessible.db")
	guardedPath := filepath.Join(env.tempRoot, "a0")
	copySmokeFixture(t, guardedPath)
	if err := os.Chmod(guardedPath, 0o000); err != nil {
		t.Fatalf("strip file permissions: %v", err)
	}
	t.Cleanup(func() {
		_ = os.Chmod(guardedPath, 0o600)
	})
	daemon := startDaemonWithDatabase(t, env.daemonPath, env.socketPath, dbPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)
	defer stopDaemonCleanly(t, daemon, env.socketPath)

	textDef := createDefinition(t, env.socketPath, "smoke_denied", "Smoke Denied", "text", "one", nil)
	changes := []schema.PropertyChangeTarget{
		textChangeTarget(t, guardedPath, textDef.PropertyID, textDef.Revision, 0, "v1"),
	}
	response := propertyCall(t, env.socketPath, "exec-denied", schema.MethodPropertyChangeExecute, map[string]any{"changes": changes})
	if response.Error == nil || response.Error.Code != schema.ErrorPermissionDenied {
		t.Fatalf("inaccessible path error=%+v, want permission_denied", response.Error)
	}
}

func runPropertyOversizedEnvelope(t *testing.T, env propertyPersistenceEnv) {
	daemon := startDaemon(t, env.daemonPath, env.socketPath)
	waitForSocket(t, daemon, env.socketPath, 15*time.Second)
	defer stopDaemonCleanly(t, daemon, env.socketPath)

	payload := bytes.Repeat([]byte("a"), schema.MaxWireBytes+5_000)
	response := udsOversizedExchange(t, env.socketPath, payload)
	if response.Error == nil || response.Error.Code != schema.ErrorRequestTooLarge {
		t.Fatalf("oversized envelope error=%+v, want request_too_large", response.Error)
	}
	if response.RequestID != "" {
		t.Fatalf("oversized envelope echoed untrustworthy request id %q", response.RequestID)
	}
}

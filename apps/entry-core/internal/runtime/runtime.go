package runtime

import (
	"sync"
)

var AppVersion = "0.1.0-dev"

type State string

const (
	StateRunning  State = "running"
	StateStopping State = "stopping"
)

type Runtime struct {
	mu                    sync.RWMutex
	state                 State
	appVersion            string
	entryService          EntryService
	propertyService       PropertyService
	workspaceID           string
	propertyQueryTokenKey [32]byte
}

func New() *Runtime {
	return newWithAppVersion(AppVersion)
}

func newWithAppVersion(appVersion string) *Runtime {
	return newWithAppVersionAndServices(appVersion, "", nil, nil)
}

// newWithAppVersionAndServices는 서비스 조합을 Runtime으로 묶는다. Property
// dispatch를 소유하는 조합의 condition query token key는 NewWithServices가
// 생성·검증한다 — DB-less 조합은 Property 메서드를 게이트에서 거절하므로 키를
// 사용하지 않는다.
func newWithAppVersionAndServices(appVersion, workspaceID string, entryService EntryService, propertyService PropertyService) *Runtime {
	return &Runtime{state: StateRunning, appVersion: appVersion, entryService: entryService, propertyService: propertyService, workspaceID: workspaceID}
}

func (runtime *Runtime) State() State {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.state
}

func (runtime *Runtime) BeginStopping() bool {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state == StateStopping {
		return false
	}
	runtime.state = StateStopping
	return true
}

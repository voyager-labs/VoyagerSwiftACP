package runtime

import (
	"crypto/rand"
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

func newWithAppVersionAndServices(appVersion, workspaceID string, entryService EntryService, propertyService PropertyService) *Runtime {
	runtime := &Runtime{state: StateRunning, appVersion: appVersion, entryService: entryService, propertyService: propertyService, workspaceID: workspaceID}
	if _, err := rand.Read(runtime.propertyQueryTokenKey[:]); err != nil {
		runtime.propertyService = nil
	}
	return runtime
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

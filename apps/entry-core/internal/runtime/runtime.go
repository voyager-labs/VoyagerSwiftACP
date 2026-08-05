package runtime

import (
	"sync"

	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

var AppVersion = "0.1.0-dev"

type State string

const (
	StateRunning  State = "running"
	StateStopping State = "stopping"
)

type Runtime struct {
	mu         sync.RWMutex
	state      State
	appVersion string
}

func New() *Runtime {
	return newWithAppVersion(AppVersion)
}

func newWithAppVersion(appVersion string) *Runtime {
	return &Runtime{
		state:      StateRunning,
		appVersion: appVersion,
	}
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

func (runtime *Runtime) Dispatch(request schema.Request) (schema.Result, *schema.ProtocolError) {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	if runtime.state != StateRunning {
		return nil, internalError()
	}

	switch request.Method {
	case schema.MethodPing:
		return schema.PingResult{Message: "pong"}, nil
	case schema.MethodHealth:
		return schema.HealthResult{Status: "healthy", State: string(StateRunning)}, nil
	case schema.MethodVersion:
		return schema.VersionResult{
			AppVersion:      runtime.appVersion,
			ProtocolVersion: schema.ProtocolVersion,
		}, nil
	default:
		return nil, internalError()
	}
}

func internalError() *schema.ProtocolError {
	return schema.NewErrorResponse("", schema.ErrorInternal).Error
}

package unixsocket

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/protocol/schema"
)

const (
	serverReadTimeout  = 2 * time.Second
	serverWriteTimeout = 2 * time.Second
	serverGraceTimeout = 5 * time.Second
	serverFinalTimeout = 2 * time.Second
)

var errHandlersDidNotStop = errors.New("Unix socket handlers did not stop within the final deadline")

type serverDurations struct {
	readTimeout  time.Duration
	writeTimeout time.Duration
	graceTimeout time.Duration
	finalTimeout time.Duration
}

type serverStartupHooks struct {
	afterBind func(string, os.FileInfo) error
}

func defaultServerDurations() serverDurations {
	return serverDurations{
		readTimeout:  serverReadTimeout,
		writeTimeout: serverWriteTimeout,
		graceTimeout: serverGraceTimeout,
		finalTimeout: serverFinalTimeout,
	}
}

type Server struct {
	path      string
	runtime   *entryruntime.Runtime
	logger    *log.Logger
	durations serverDurations
	listener  *net.UnixListener
	owned     os.FileInfo

	mu              sync.Mutex
	stopping        bool
	active          map[net.Conn]struct{}
	handle          func(net.Conn)
	beforeAdmission func()
	graceStarted    func()
	handlers        sync.WaitGroup
	acceptDone      chan struct{}
}

func NewServer(path string, runtime *entryruntime.Runtime, logger *log.Logger) (*Server, error) {
	return newServer(path, runtime, logger, defaultServerDurations())
}

func newServer(path string, runtime *entryruntime.Runtime, logger *log.Logger, durations serverDurations) (*Server, error) {
	return newServerWithHooks(path, runtime, logger, durations, serverStartupHooks{})
}

func newServerWithHooks(
	path string,
	runtime *entryruntime.Runtime,
	logger *log.Logger,
	durations serverDurations,
	hooks serverStartupHooks,
) (*Server, error) {
	if runtime == nil {
		return nil, errors.New("runtime is required")
	}
	parent, err := validateSocketPath(path, os.Geteuid())
	if err != nil {
		return nil, err
	}

	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, fmt.Errorf("listen on Unix socket: %w", err)
	}
	listener.SetUnlinkOnClose(false)

	owned, err := os.Lstat(path)
	if err != nil {
		_ = listener.Close()
		return nil, fmt.Errorf("inspect bound Unix socket: %w", err)
	}
	rollback := func(cause error) (*Server, error) {
		_ = listener.Close()
		if cleanupErr := removeIfSame(path, owned); cleanupErr != nil {
			return nil, errors.Join(cause, cleanupErr)
		}
		return nil, cause
	}
	if owned.Mode()&os.ModeSocket == 0 {
		return rollback(errors.New("bound destination is not a socket"))
	}
	if hooks.afterBind != nil {
		if err := hooks.afterBind(path, owned); err != nil {
			return rollback(err)
		}
	}
	if err := os.Chmod(path, 0o600); err != nil {
		return rollback(fmt.Errorf("set Unix socket mode: %w", err))
	}
	current, err := os.Lstat(path)
	if err != nil {
		return rollback(fmt.Errorf("reinspect Unix socket: %w", err))
	}
	if !os.SameFile(owned, current) || current.Mode()&os.ModeSocket == 0 || current.Mode().Perm() != 0o600 {
		return rollback(errors.New("Unix socket identity or mode changed during startup"))
	}
	currentParent, err := os.Lstat(filepath.Dir(path))
	if err != nil || !os.SameFile(parent, currentParent) {
		return rollback(errors.New("Unix socket parent changed during startup"))
	}
	if err := validateSecureDirectory(currentParent, os.Geteuid()); err != nil {
		return rollback(err)
	}

	server := &Server{
		path:       path,
		runtime:    runtime,
		logger:     logger,
		durations:  durations,
		listener:   listener,
		owned:      owned,
		active:     make(map[net.Conn]struct{}),
		acceptDone: make(chan struct{}),
	}
	server.handle = server.handleConnection
	return server, nil
}

func validateSocketPath(path string, effectiveUID int) (os.FileInfo, error) {
	if !filepath.IsAbs(path) {
		return nil, errors.New("Unix socket path must be absolute")
	}
	if len([]byte(path)) >= len(syscall.RawSockaddrUnix{}.Path) {
		return nil, errors.New("Unix socket path is too long")
	}

	parentPath := filepath.Dir(path)
	parent, err := os.Lstat(parentPath)
	if os.IsNotExist(err) {
		if err := os.Mkdir(parentPath, 0o700); err != nil {
			return nil, fmt.Errorf("create Unix socket parent: %w", err)
		}
		parent, err = os.Lstat(parentPath)
	}
	if err != nil {
		return nil, fmt.Errorf("inspect Unix socket parent: %w", err)
	}
	if err := validateSecureDirectory(parent, effectiveUID); err != nil {
		return nil, err
	}
	if _, err := os.Lstat(path); err == nil {
		return nil, errors.New("Unix socket destination already exists")
	} else if !os.IsNotExist(err) {
		return nil, fmt.Errorf("inspect Unix socket destination: %w", err)
	}
	return parent, nil
}

func validateSecureDirectory(info os.FileInfo, effectiveUID int) error {
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return errors.New("Unix socket parent must be a non-symlink directory")
	}
	if info.Mode().Perm() != 0o700 {
		return errors.New("Unix socket parent mode must be 0700")
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != effectiveUID {
		return errors.New("Unix socket parent must be owned by the effective UID")
	}
	return nil
}

func (server *Server) Serve() error {
	defer close(server.acceptDone)
	for {
		connection, err := server.listener.AcceptUnix()
		if err != nil {
			server.mu.Lock()
			stopping := server.stopping
			server.mu.Unlock()
			if stopping || errors.Is(err, net.ErrClosed) {
				return nil
			}
			return fmt.Errorf("accept Unix socket connection: %w", err)
		}
		if err := connection.SetReadDeadline(time.Now().Add(server.durations.readTimeout)); err != nil {
			_ = connection.Close()
			continue
		}

		server.mu.Lock()
		beforeAdmission := server.beforeAdmission
		server.mu.Unlock()
		if beforeAdmission != nil {
			beforeAdmission()
		}

		server.mu.Lock()
		if server.stopping {
			server.mu.Unlock()
			_ = connection.Close()
			continue
		}
		server.active[connection] = struct{}{}
		server.handlers.Add(1)
		handler := server.handle
		server.mu.Unlock()

		go server.runHandler(connection, handler)
	}
}

func (server *Server) runHandler(connection net.Conn, handler func(net.Conn)) {
	defer func() {
		if recover() != nil && server.logger != nil {
			server.logger.Print("Unix socket connection handler panicked")
		}
		_ = connection.Close()
		server.mu.Lock()
		delete(server.active, connection)
		server.mu.Unlock()
		server.handlers.Done()
	}()
	handler(connection)
}

func (server *Server) handleConnection(connection net.Conn) {
	wire, err := io.ReadAll(io.LimitReader(connection, schema.MaxWireBytes+1))
	if err != nil {
		return
	}

	var response schema.Response
	if len(wire) > schema.MaxWireBytes {
		response = schema.NewErrorResponse("", schema.ErrorRequestTooLarge)
	} else {
		request, trustworthyID, protocolError := schema.DecodeRequest(wire)
		if protocolError != nil {
			response = schema.NewErrorResponse(trustworthyID, protocolError.Code)
		} else {
			result, dispatchError := server.runtime.Dispatch(request)
			if dispatchError != nil {
				response = schema.NewErrorResponse(trustworthyID, dispatchError.Code)
			} else {
				response = schema.NewSuccessResponse(trustworthyID, result)
			}
		}
	}

	encoded := schema.EncodeResponse(response)
	if err := connection.SetWriteDeadline(time.Now().Add(server.durations.writeTimeout)); err != nil {
		return
	}
	for len(encoded) > 0 {
		written, err := connection.Write(encoded)
		if err != nil || written <= 0 {
			return
		}
		encoded = encoded[written:]
	}
}

func (server *Server) Shutdown(force <-chan struct{}) error {
	server.mu.Lock()
	server.stopping = true
	server.runtime.BeginStopping()
	server.mu.Unlock()
	closeErr := server.listener.Close()

	<-server.acceptDone
	handlersDone := make(chan struct{})
	go func() {
		server.handlers.Wait()
		close(handlersDone)
	}()
	server.mu.Lock()
	graceStarted := server.graceStarted
	server.mu.Unlock()
	if graceStarted != nil {
		graceStarted()
	}

	graceExpired := false
	graceTimer := time.NewTimer(server.durations.graceTimeout)
	select {
	case <-handlersDone:
		graceTimer.Stop()
	case <-graceTimer.C:
		graceExpired = true
	case <-force:
		graceExpired = true
		graceTimer.Stop()
	}

	var waitErr error
	if graceExpired {
		server.mu.Lock()
		connections := make([]net.Conn, 0, len(server.active))
		for connection := range server.active {
			connections = append(connections, connection)
		}
		server.mu.Unlock()
		for _, connection := range connections {
			_ = connection.Close()
		}

		finalTimer := time.NewTimer(server.durations.finalTimeout)
		select {
		case <-handlersDone:
			finalTimer.Stop()
		case <-finalTimer.C:
			waitErr = errHandlersDidNotStop
		}
	}

	cleanupErr := removeIfSame(server.path, server.owned)
	if closeErr != nil && !errors.Is(closeErr, net.ErrClosed) {
		return errors.Join(closeErr, waitErr, cleanupErr)
	}
	return errors.Join(waitErr, cleanupErr)
}

func removeIfSame(path string, owned os.FileInfo) error {
	current, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect owned Unix socket: %w", err)
	}
	if !os.SameFile(owned, current) {
		return nil
	}
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove owned Unix socket: %w", err)
	}
	return nil
}

func (server *Server) setHandler(handler func(net.Conn)) {
	server.mu.Lock()
	defer server.mu.Unlock()
	server.handle = handler
}

func (server *Server) setBeforeAdmission(beforeAdmission func()) {
	server.mu.Lock()
	defer server.mu.Unlock()
	server.beforeAdmission = beforeAdmission
}

func (server *Server) setGraceStarted(graceStarted func()) {
	server.mu.Lock()
	defer server.mu.Unlock()
	server.graceStarted = graceStarted
}

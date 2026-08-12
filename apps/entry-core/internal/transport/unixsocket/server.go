package unixsocket

import (
	"context"
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

var (
	errHandlersDidNotStop = errors.New("Unix socket handlers did not stop within the final deadline")
	bindUmaskMu           sync.Mutex
)

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
	// lifecycleLock은 같은 advisory lock을 따르는 Entry Core 인스턴스의 startup과 cleanup만 직렬화한다.
	lifecycleLock *os.File

	mu              sync.Mutex
	stopping        bool
	active          map[net.Conn]struct{}
	handle          func(net.Conn)
	beforeAdmission func()
	graceStarted    func()
	beforeRemove    func()
	handlers        sync.WaitGroup
	acceptDone      chan struct{}
	shutdownOnce    sync.Once
	shutdownErr     error
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
	effectiveUID := os.Geteuid()
	parent, err := validateSocketParent(path, effectiveUID)
	if err != nil {
		return nil, err
	}
	lifecycleLock, err := acquireLifecycleLock(path+".lock", effectiveUID)
	if err != nil {
		return nil, err
	}
	failWithLock := func(cause error) (*Server, error) {
		return nil, errors.Join(cause, lifecycleLock.Close())
	}

	currentParent, err := os.Lstat(filepath.Dir(path))
	if err != nil {
		return failWithLock(fmt.Errorf("reinspect Unix socket parent after locking: %w", err))
	}
	if !os.SameFile(parent, currentParent) {
		return failWithLock(errors.New("Unix socket parent changed while acquiring lifecycle lock"))
	}
	if err := validateSecureDirectory(currentParent, effectiveUID); err != nil {
		return failWithLock(err)
	}
	if err := validateSocketDestination(path); err != nil {
		return failWithLock(err)
	}

	listener, err := listenUnixPrivate(path)
	if err != nil {
		return failWithLock(err)
	}
	listener.SetUnlinkOnClose(false)

	owned, err := os.Lstat(path)
	if err != nil {
		closeErr := listener.Close()
		return failWithLock(errors.Join(fmt.Errorf("inspect bound Unix socket: %w", err), closeErr))
	}
	rollback := func(cause error) (*Server, error) {
		closeErr := listener.Close()
		cleanupErr := removeIfSame(path, owned, nil)
		lockErr := lifecycleLock.Close()
		return nil, errors.Join(cause, closeErr, cleanupErr, lockErr)
	}
	if owned.Mode()&os.ModeSocket == 0 || owned.Mode().Perm() != 0o600 {
		return rollback(errors.New("bound destination is not a socket with exact mode 0600"))
	}
	if hooks.afterBind != nil {
		if err := hooks.afterBind(path, owned); err != nil {
			return rollback(err)
		}
	}
	current, err := os.Lstat(path)
	if err != nil {
		return rollback(fmt.Errorf("reinspect Unix socket: %w", err))
	}
	if !os.SameFile(owned, current) || current.Mode()&os.ModeSocket == 0 || current.Mode().Perm() != 0o600 {
		return rollback(errors.New("Unix socket identity or mode changed during startup"))
	}
	currentParent, err = os.Lstat(filepath.Dir(path))
	if err != nil || !os.SameFile(parent, currentParent) {
		return rollback(errors.New("Unix socket parent changed during startup"))
	}
	if err := validateSecureDirectory(currentParent, effectiveUID); err != nil {
		return rollback(err)
	}

	server := &Server{
		path:          path,
		runtime:       runtime,
		logger:        logger,
		durations:     durations,
		listener:      listener,
		owned:         owned,
		lifecycleLock: lifecycleLock,
		active:        make(map[net.Conn]struct{}),
		acceptDone:    make(chan struct{}),
	}
	server.handle = server.handleConnection
	return server, nil
}

func listenUnixPrivate(path string) (*net.UnixListener, error) {
	bindUmaskMu.Lock()
	originalMask := syscall.Umask(0o777)
	syscall.Umask(originalMask | 0o177)
	defer func() {
		syscall.Umask(originalMask)
		bindUmaskMu.Unlock()
	}()

	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, fmt.Errorf("listen on Unix socket: %w", err)
	}
	return listener, nil
}

func validateSocketPath(path string, effectiveUID int) (os.FileInfo, error) {
	parent, err := validateSocketParent(path, effectiveUID)
	if err != nil {
		return nil, err
	}
	if err := validateSocketDestination(path); err != nil {
		return nil, err
	}
	return parent, nil
}

func validateSocketParent(path string, effectiveUID int) (os.FileInfo, error) {
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
	return parent, nil
}

func validateSocketDestination(path string) error {
	if _, err := os.Lstat(path); err == nil {
		return errors.New("Unix socket destination already exists")
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("inspect Unix socket destination: %w", err)
	}
	return nil
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
			response = server.runtime.Dispatch(context.Background(), request)
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
	server.shutdownOnce.Do(func() {
		server.shutdownErr = server.shutdown(force)
	})
	return server.shutdownErr
}

func (server *Server) shutdown(force <-chan struct{}) error {
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

	server.mu.Lock()
	beforeRemove := server.beforeRemove
	server.mu.Unlock()
	cleanupErr := removeIfSame(server.path, server.owned, beforeRemove)
	lockErr := server.lifecycleLock.Close()
	if closeErr != nil && !errors.Is(closeErr, net.ErrClosed) {
		return errors.Join(closeErr, waitErr, cleanupErr, lockErr)
	}
	return errors.Join(waitErr, cleanupErr, lockErr)
}

// removeIfSame은 호출자가 lifecycle lock을 보유한 상태에서 사용하는 best-effort identity guard다.
// macOS/POSIX에는 atomic unlink-if-same-inode가 없으므로 같은 advisory lock을 따르는 참여자만 보존을 보장한다.
func removeIfSame(path string, owned os.FileInfo, beforeRemove func()) error {
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
	if beforeRemove != nil {
		beforeRemove()
	}
	if err := os.Remove(path); os.IsNotExist(err) {
		return nil
	} else if err != nil {
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

func (server *Server) setBeforeRemove(beforeRemove func()) {
	server.mu.Lock()
	defer server.mu.Unlock()
	server.beforeRemove = beforeRemove
}

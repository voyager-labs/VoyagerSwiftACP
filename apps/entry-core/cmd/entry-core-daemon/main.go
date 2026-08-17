package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	entryruntime "github.com/voyager-labs/voyager-app/apps/entry-core/internal/runtime"
	"github.com/voyager-labs/voyager-app/apps/entry-core/internal/transport/unixsocket"
)

const daemonUsage = "usage: entry-core-daemon --socket <absolute-path>"

type daemonServer interface {
	Serve() error
	Shutdown(<-chan struct{}) error
}

type daemonDependencies struct {
	newServer    func(string, *log.Logger) (daemonServer, error)
	signalSource func() (<-chan os.Signal, func())
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, productionDependencies()))
}

func run(args []string, stdout io.Writer, stderr io.Writer, dependencies daemonDependencies) int {
	_ = stdout
	socketPath, ok := parseDaemonArgs(args)
	if !ok {
		fmt.Fprintln(stderr, daemonUsage)
		return 2
	}

	logger := log.New(stderr, "entry-core-daemon: ", 0)
	signals, stopSignals := dependencies.signalSource()
	defer stopSignals()

	server, err := dependencies.newServer(socketPath, logger)
	if err != nil {
		logger.Printf("startup failed: %v", err)
		return 1
	}

	serveDone := make(chan error, 1)
	go func() {
		serveDone <- server.Serve()
	}()
	logger.Print("started in foreground")

	select {
	case serveErr := <-serveDone:
		if serveErr != nil {
			logger.Printf("serve failed: %v", serveErr)
		} else {
			logger.Print("serve stopped unexpectedly")
		}
		if shutdownErr := server.Shutdown(nil); shutdownErr != nil {
			logger.Printf("cleanup after serve failure failed: %v", shutdownErr)
		}
		return 1
	case received := <-signals:
		logger.Printf("received %s; shutting down", received)
	}

	force := make(chan struct{})
	shutdownDone := make(chan error, 1)
	go func() {
		shutdownDone <- server.Shutdown(force)
	}()

	forceTriggered := false
	for {
		select {
		case received := <-signals:
			if !forceTriggered {
				close(force)
				forceTriggered = true
				logger.Printf("received second %s; forcing shutdown", received)
			}
		case shutdownErr := <-shutdownDone:
			serveErr := <-serveDone
			if shutdownErr != nil {
				logger.Printf("shutdown failed: %v", shutdownErr)
				return 1
			}
			if serveErr != nil {
				logger.Printf("serve failed during shutdown: %v", serveErr)
				return 1
			}
			logger.Print("stopped")
			return 0
		}
	}
}

func parseDaemonArgs(args []string) (string, bool) {
	if len(args) != 2 || args[0] != "--socket" || args[1] == "" || !filepath.IsAbs(args[1]) {
		return "", false
	}
	return args[1], true
}

func productionDependencies() daemonDependencies {
	return daemonDependencies{
		newServer: func(path string, logger *log.Logger) (daemonServer, error) {
			return unixsocket.NewServer(path, entryruntime.New(), logger)
		},
		signalSource: func() (<-chan os.Signal, func()) {
			signals := make(chan os.Signal, 2)
			signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
			return signals, func() { signal.Stop(signals) }
		},
	}
}

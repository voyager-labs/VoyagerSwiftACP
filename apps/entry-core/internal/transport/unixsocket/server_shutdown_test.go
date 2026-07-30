package unixsocket

import (
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"
)

func TestShutdownGraceCompletion(t *testing.T) {
	durations := testDurations()
	durations.graceTimeout = time.Second
	server, path := runningServer(t, nil, durations)
	started := make(chan struct{})
	release := make(chan struct{})
	server.setHandler(func(connection net.Conn) {
		close(started)
		<-release
		_, _ = connection.Write([]byte("complete"))
	})
	connection := dialUnix(t, path)
	<-started
	shutdownDone := make(chan error, 1)
	go func() { shutdownDone <- server.Shutdown(nil) }()
	close(release)
	if err := <-shutdownDone; err != nil {
		t.Fatalf("Shutdown() error = %v", err)
	}
	response, err := io.ReadAll(connection)
	if err != nil || len(response) == 0 {
		t.Fatalf("grace response length = %d, error = %v", len(response), err)
	}
	_ = connection.Close()
}

func TestShutdownForceClosesStalledClient(t *testing.T) {
	durations := testDurations()
	durations.graceTimeout = 20 * time.Millisecond
	durations.finalTimeout = 200 * time.Millisecond
	server, path := runningServer(t, nil, durations)
	connection := dialUnix(t, path)
	waitForActive(t, server, 1)
	started := time.Now()
	shutdownServer(t, server, nil)
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Fatalf("Shutdown() took %v", elapsed)
	}
	if _, err := connection.Write([]byte("x")); err == nil {
		_ = connection.SetReadDeadline(time.Now().Add(20 * time.Millisecond))
		if _, readErr := connection.Read(make([]byte, 1)); readErr == nil {
			t.Fatal("stalled connection remained open")
		}
	}
	_ = connection.Close()
}

func TestShutdownSecondTriggerSkipsGrace(t *testing.T) {
	durations := testDurations()
	durations.graceTimeout = time.Second
	server, path := runningServer(t, nil, durations)
	connection := dialUnix(t, path)
	waitForActive(t, server, 1)
	force := make(chan struct{})
	graceStarted := make(chan struct{})
	server.setGraceStarted(func() { close(graceStarted) })
	started := time.Now()
	shutdownDone := make(chan error, 1)
	go func() { shutdownDone <- server.Shutdown(force) }()
	<-graceStarted
	close(force)
	if err := <-shutdownDone; err != nil {
		t.Fatalf("Shutdown() error = %v", err)
	}
	if elapsed := time.Since(started); elapsed > 300*time.Millisecond {
		t.Fatalf("forced Shutdown() took %v", elapsed)
	}
	_ = connection.Close()
}

func TestShutdownBoundedFinalWait(t *testing.T) {
	durations := testDurations()
	durations.graceTimeout = 10 * time.Millisecond
	durations.finalTimeout = 30 * time.Millisecond
	server, path := runningServer(t, nil, durations)
	block := make(chan struct{})
	server.setHandler(func(connection net.Conn) {
		<-block
	})
	connection := dialUnix(t, path)
	waitForActive(t, server, 1)
	started := time.Now()
	err := server.Shutdown(nil)
	if err == nil {
		t.Fatal("Shutdown() succeeded while handler did not converge")
	}
	if elapsed := time.Since(started); elapsed > 300*time.Millisecond {
		t.Fatalf("bounded Shutdown() took %v", elapsed)
	}
	close(block)
	_ = connection.Close()
}

func TestAcceptRaceDoesNotStartHandlerAfterStopping(t *testing.T) {
	server, path := runningServer(t, nil, testDurations())
	accepted := make(chan struct{})
	releaseAdmission := make(chan struct{})
	server.setBeforeAdmission(func() {
		close(accepted)
		<-releaseAdmission
	})
	var handlerStarts atomic.Int32
	server.setHandler(func(net.Conn) { handlerStarts.Add(1) })

	connection := dialUnix(t, path)
	<-accepted
	shutdownDone := make(chan error, 1)
	go func() { shutdownDone <- server.Shutdown(nil) }()
	waitForStopping(t, server)
	close(releaseAdmission)
	if err := <-shutdownDone; err != nil {
		t.Fatalf("Shutdown() error = %v", err)
	}
	if starts := handlerStarts.Load(); starts != 0 {
		t.Fatalf("handler starts after shutdown admission closed = %d, want 0", starts)
	}
	_ = connection.Close()
}

func waitForActive(t *testing.T, server *Server, want int) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		server.mu.Lock()
		active := len(server.active)
		server.mu.Unlock()
		if active == want {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("active connections never reached %d", want)
}

func waitForStopping(t *testing.T, server *Server) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		server.mu.Lock()
		stopping := server.stopping
		server.mu.Unlock()
		if stopping {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("shutdown admission did not close")
}

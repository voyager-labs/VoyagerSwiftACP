package unixsocket

import (
	"errors"
	"fmt"
	"os"
	"syscall"
)

func acquireLifecycleLock(path string, effectiveUID int) (*os.File, error) {
	flags := syscall.O_RDWR | syscall.O_NOFOLLOW | syscall.O_CLOEXEC | syscall.O_NONBLOCK
	fd, err := syscall.Open(path, flags|syscall.O_CREAT|syscall.O_EXCL, 0o600)
	created := err == nil
	if errors.Is(err, syscall.EEXIST) {
		fd, err = syscall.Open(path, flags, 0)
	}
	if err != nil {
		return nil, fmt.Errorf("open Unix socket lifecycle lock: %w", err)
	}

	file := os.NewFile(uintptr(fd), path)
	if file == nil {
		_ = syscall.Close(fd)
		return nil, errors.New("open Unix socket lifecycle lock: invalid file descriptor")
	}
	fail := func(cause error) (*os.File, error) {
		return nil, errors.Join(cause, file.Close())
	}
	if created {
		if err := file.Chmod(0o600); err != nil {
			return fail(fmt.Errorf("set Unix socket lifecycle lock mode: %w", err))
		}
	}
	if err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return fail(fmt.Errorf("lock Unix socket lifecycle: %w", err))
	}
	if err := validateLifecycleLock(file, path, effectiveUID); err != nil {
		return fail(err)
	}
	return file, nil
}

func validateLifecycleLock(file *os.File, path string, effectiveUID int) error {
	fdInfo, err := file.Stat()
	if err != nil {
		return fmt.Errorf("inspect Unix socket lifecycle lock descriptor: %w", err)
	}
	pathInfo, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("inspect Unix socket lifecycle lock path: %w", err)
	}
	if !fdInfo.Mode().IsRegular() || !pathInfo.Mode().IsRegular() {
		return errors.New("Unix socket lifecycle lock must be a regular file")
	}
	if fdInfo.Mode().Perm() != 0o600 || pathInfo.Mode().Perm() != 0o600 {
		return errors.New("Unix socket lifecycle lock mode must be 0600")
	}
	stat, ok := fdInfo.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != effectiveUID {
		return errors.New("Unix socket lifecycle lock must be owned by the effective UID")
	}
	if stat.Nlink != 1 {
		return errors.New("Unix socket lifecycle lock link count must be one")
	}
	if !os.SameFile(fdInfo, pathInfo) {
		return errors.New("Unix socket lifecycle lock pathname and descriptor differ")
	}
	return nil
}

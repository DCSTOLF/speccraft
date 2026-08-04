//go:build unix

package main

import "syscall"

// tryFlockExclusive attempts a non-blocking exclusive advisory lock on fd.
// It returns (true, nil) when the lock was acquired, (false, nil) when the lock
// is currently held by someone else (EWOULDBLOCK / EAGAIN — they alias on
// linux, differ on macOS, both mean "still held"), and (false, err) on any
// other error.
func tryFlockExclusive(fd int) (bool, error) {
	err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
	if err == nil {
		return true, nil
	}
	if err == syscall.EWOULDBLOCK || err == syscall.EAGAIN {
		return false, nil
	}
	return false, err
}

// releaseFlock drops the advisory lock held on fd. The kernel also releases it
// automatically when the owning process exits, so this is best-effort cleanup
// on the normal path (crash-safety does not depend on it).
func releaseFlock(fd int) error {
	return syscall.Flock(fd, syscall.LOCK_UN)
}

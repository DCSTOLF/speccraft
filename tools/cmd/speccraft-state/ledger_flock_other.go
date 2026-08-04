//go:build !unix

package main

import "errors"

// On non-unix platforms speccraft ships no binary (spec 0045 AC6: linux + macOS
// only). These stubs make such a build fail loudly at the lock site rather than
// silently skipping mutual exclusion.

func tryFlockExclusive(fd int) (bool, error) {
	return false, errors.New("ledger locking unsupported on this platform")
}

func releaseFlock(fd int) error {
	return errors.New("ledger locking unsupported on this platform")
}

package device

import "testing"

func TestClockLockRejectsOverlappingProcesses(t *testing.T) {
	release, err := AcquireClockLock()
	if err != nil {
		t.Fatal(err)
	}

	if second, err := AcquireClockLock(); err == nil {
		second()
		release()
		t.Fatal("accepted overlapping sync")
	}
	release()
	next, err := AcquireClockLock()
	if err != nil {
		t.Fatal("lock not released", err)
	}
	next()
}

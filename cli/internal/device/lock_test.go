package device

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestClockLockPathUsesTempDir(t *testing.T) {
	path := clockLockPath()
	if filepath.Dir(path) != filepath.Clean(os.TempDir()) {
		t.Fatalf("lock path %s is outside the temp dir", path)
	}
	want := fmt.Sprintf("cidoo-clock-%d.lock", os.Getuid())
	if filepath.Base(path) != want {
		t.Fatalf("lock file %s, want %s", filepath.Base(path), want)
	}
}

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

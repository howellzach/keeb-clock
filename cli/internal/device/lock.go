package device

import (
	"fmt"
	"golang.org/x/sys/unix"
	"os"
)

// Both CLI and app use this lock; a second process never interleaves HID reports.
func AcquireClockLock() (func(), error) {
	path := fmt.Sprintf("/private/tmp/cidoo-clock-%d.lock", os.Getuid())
	fd, err := unix.Open(path, unix.O_CREAT|unix.O_RDWR|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0600)
	if err != nil {
		return nil, err
	}
	var stat unix.Stat_t
	if err = unix.Fstat(fd, &stat); err != nil || stat.Uid != uint32(os.Getuid()) || stat.Mode&unix.S_IFMT != unix.S_IFREG {
		unix.Close(fd)
		return nil, fmt.Errorf("unsafe clock lock file")
	}
	if err = unix.Flock(fd, unix.LOCK_EX|unix.LOCK_NB); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("another clock sync is already running")
	}
	return func() { unix.Flock(fd, unix.LOCK_UN); unix.Close(fd) }, nil
}

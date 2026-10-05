package device

import (
	"fmt"
	"io"

	"github.com/sstallion/go-hid"
)

type Info = hid.DeviceInfo

func Init() error { return hid.Init() }

func Exit() { hid.Exit() }

func Enumerate(vendorID, productID uint16) ([]Info, error) {
	var out []Info
	if err := hid.Enumerate(vendorID, productID, func(info *hid.DeviceInfo) error {
		out = append(out, *info)
		return nil
	}); err != nil {
		return nil, err
	}
	return out, nil
}

func OpenPath(path string) (*hid.Device, error) {
	if path == "" {
		return nil, fmt.Errorf("empty HID path")
	}
	return hid.OpenPath(path)
}

func WritePacket(dev *hid.Device, packet [64]byte) error {
	n, err := dev.Write(packet[:])
	if err == nil && n != len(packet) {
		return io.ErrShortWrite
	}
	return err
}

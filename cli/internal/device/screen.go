package device

import "fmt"

const (
	UsagePageScreen = uint16(0xff1c)
	UsageScreen     = uint16(0x0092)
)

func FilterScreenInterfaces(in []Info) []Info {
	out := make([]Info, 0, len(in))
	for _, d := range in {
		if d.UsagePage == UsagePageScreen && d.Usage == UsageScreen {
			out = append(out, d)
		}
	}
	return out
}

func PickByPath(devs []Info, path string) (Info, error) {
	for _, d := range devs {
		if d.Path == path {
			return d, nil
		}
	}
	return Info{}, fmt.Errorf("no device with path %q", path)
}

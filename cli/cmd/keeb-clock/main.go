package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "image/jpeg"
	_ "image/png"

	"github.com/howellzach/keeb-clock/internal/device"
	"github.com/howellzach/keeb-clock/internal/imageconv"
	"github.com/howellzach/keeb-clock/internal/protocol"
)

const (
	vendorID  = 0x320f
	productID = 0x5055
)

// Set from Config/Version.xcconfig by scripts/build-cli.sh.
var version = "dev"
var buildNumber = "0"

func main() {
	log.SetFlags(0)
	if err := run(os.Args[1:]); err != nil {
		if strings.HasPrefix(err.Error(), "usage:") {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(2)
		}
		log.Fatal(err)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return usageError(rootUsage())
	}

	switch args[0] {
	case "--version", "version":
		if len(args) != 1 {
			return usageError(rootUsage())
		}
		fmt.Printf("keeb-clock %s (build %s)\n", version, buildNumber)
		return nil
	case "devices":
		return cmdDevices(args[1:])
	case "convert":
		return cmdConvert(args[1:])
	case "set-image":
		return cmdSetImage(args[1:])
	case "sync-time":
		return cmdSyncTime(args[1:])
	case "-h", "--help", "help":
		fmt.Print(rootUsage())
		return nil
	default:
		return usageError(rootUsage())
	}
}

func rootUsage() string {
	exe := filepath.Base(os.Args[0])
	return fmt.Sprintf(`Usage:
  %s devices
  %s convert --out <frame.rgb565> [flags] <image.(png|jpg|jpeg)>
  %s set-image [flags] <image.(png|jpg|jpeg)>
  %s sync-time [flags]

Flags (convert / set-image):
  --width <px>        Target width (default 160)
  --height <px>       Target height (default 96)
  --rotate 0|90|180|270
  --swap-bytes        Swap RGB565 byte order (lo/hi)
  --pad-to <bytes>    Pad frame to this many bytes (default 32768; 0 disables)

Flags (set-image):
  --dry-run           Do not write HID (default true)
  --verbose           Print extra details

Flags (sync-time):
  --dry-run           Do not write config to HID
  --path <hidpath>    Use a specific HID path (otherwise auto-pick)
  --slot <n>          Slot index override (default: read active slot at offset 0)
  --timeout <ms>      Read timeout (default 1500)
  --utc               Use UTC instead of local time
  --verbose           Print extra details
  --json              Machine-readable sync result
`, exe, exe, exe, exe)
}

func usageError(msg string) error { return fmt.Errorf("usage:\n%s", msg) }

func cmdDevices(args []string) error {
	fs := flag.NewFlagSet("devices", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	verbose := fs.Bool("verbose", false, "print full device info blocks")
	if err := fs.Parse(args); err != nil {
		return err
	}

	if err := device.Init(); err != nil {
		return err
	}
	defer device.Exit()

	devs, err := device.Enumerate(vendorID, productID)
	if err != nil {
		return err
	}

	if len(devs) == 0 {
		return fmt.Errorf("no CIDOO ABM066 devices found (VID=0x%04x PID=0x%04x)", vendorID, productID)
	}

	sort.Slice(devs, func(i, j int) bool {
		if devs[i].InterfaceNbr != devs[j].InterfaceNbr {
			return devs[i].InterfaceNbr < devs[j].InterfaceNbr
		}
		if devs[i].UsagePage != devs[j].UsagePage {
			return devs[i].UsagePage < devs[j].UsagePage
		}
		return devs[i].Usage < devs[j].Usage
	})

	if *verbose {
		fmt.Println("Found CIDOO ABM066 HID devices:")
		fmt.Println()
		for _, d := range devs {
			fmt.Printf("Path: %s\n", d.Path)
			fmt.Printf("Manufacturer: %s\n", d.MfrStr)
			fmt.Printf("Product: %s\n", d.ProductStr)
			fmt.Printf("Serial: %s\n", d.SerialNbr)
			fmt.Printf("Interface: %d\n", d.InterfaceNbr)
			fmt.Printf("UsagePage: 0x%x\n", d.UsagePage)
			fmt.Printf("Usage: 0x%x\n", d.Usage)
			fmt.Println()
		}
		return nil
	}

	fmt.Println("Found CIDOO ABM066 HID interfaces:")
	fmt.Println("Interface  UsagePage  Usage    Kind    Path")
	for _, d := range devs {
		kind := ""
		switch {
		case d.UsagePage == device.UsagePageScreen && d.Usage == device.UsageScreen:
			kind = "screen"
		case d.UsagePage == 0x0001 && d.Usage == 0x0006:
			kind = "keyboard"
		case d.UsagePage == 0x000c && d.Usage == 0x0001:
			kind = "consumer"
		default:
			kind = "other"
		}

		fmt.Printf("%9d  0x%04x    0x%04x  %-7s %s\n", d.InterfaceNbr, d.UsagePage, d.Usage, kind, d.Path)
	}
	return nil
}

type imageFlags struct {
	width     int
	height    int
	rotate    int
	swapBytes bool
	padTo     int
}

func (f *imageFlags) add(fs *flag.FlagSet) {
	fs.IntVar(&f.width, "width", 160, "target width (px)")
	fs.IntVar(&f.height, "height", 96, "target height (px)")
	fs.IntVar(&f.rotate, "rotate", 0, "rotate 0|90|180|270")
	fs.BoolVar(&f.swapBytes, "swap-bytes", false, "swap RGB565 bytes (lo/hi)")
	fs.IntVar(&f.padTo, "pad-to", 32768, "pad frame to this many bytes (0 disables)")
}

func cmdConvert(args []string) error {
	fs := flag.NewFlagSet("convert", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	var outPath string
	var flags imageFlags
	flags.add(fs)
	fs.StringVar(&outPath, "out", "", "output file path")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 || outPath == "" {
		return usageError("keeb-clock convert <image.png> --out <frame.rgb565>\n")
	}

	inPath := fs.Arg(0)
	info, frame, err := buildFrame(inPath, flags)
	if err != nil {
		return err
	}

	if err := os.WriteFile(outPath, frame, 0o644); err != nil {
		return err
	}

	fmt.Printf("Input: %s\n", inPath)
	fmt.Printf("Decoded size: %dx%d\n", info.decodedW, info.decodedH)
	fmt.Printf("Target size: %dx%d\n", flags.width, flags.height)
	fmt.Printf("RGB565 bytes: %d\n", info.rgb565Bytes)
	fmt.Printf("Padded bytes: %d\n", len(frame))
	fmt.Printf("Wrote: %s\n", outPath)
	return nil
}

func cmdSetImage(args []string) error {
	fs := flag.NewFlagSet("set-image", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	var flags imageFlags
	flags.add(fs)

	dryRun := fs.Bool("dry-run", true, "do not write HID")
	verbose := fs.Bool("verbose", false, "print extra details")

	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return usageError("keeb-clock set-image <image.png> --dry-run [flags]\n")
	}

	inPath := fs.Arg(0)
	info, frame, err := buildFrame(inPath, flags)
	if err != nil {
		return err
	}

	packets := protocol.BuildImageUploadPackets(frame)

	fmt.Printf("Input: %s\n", inPath)
	fmt.Printf("Decoded size: %dx%d\n", info.decodedW, info.decodedH)
	fmt.Printf("Target size: %dx%d\n", flags.width, flags.height)
	fmt.Printf("RGB565 bytes: %d\n", info.rgb565Bytes)
	fmt.Printf("Padded bytes: %d\n", len(frame))
	fmt.Printf("Payload bytes per packet: %d\n", protocol.MaxPayloadSize)
	fmt.Printf("Packets required: %d (begin + %d chunks + commit)\n", len(packets), len(packets)-2)

	if *verbose {
		fmt.Printf("Rotate: %d\n", flags.rotate)
		fmt.Printf("Swap bytes: %v\n", flags.swapBytes)
		fmt.Printf("Pad-to: %d\n", flags.padTo)

		if len(packets) > 0 {
			fmt.Printf("First packet: %s\n", shortHex(packets[0][:], 24))
		}
		if len(packets) > 1 {
			fmt.Printf("First chunk: %s\n", shortHex(packets[1][:], 24))
		}
	}

	if *dryRun {
		fmt.Println("Dry run only. No HID writes performed.")
		return nil
	}

	return fmt.Errorf("set-image is dry-run only for now (HID writes not implemented)")
}

type frameInfo struct {
	decodedW    int
	decodedH    int
	rgb565Bytes int
}

func buildFrame(inPath string, flags imageFlags) (frameInfo, []byte, error) {
	if flags.width < 1 || flags.width > 512 || flags.height < 1 || flags.height > 512 || flags.padTo < 0 || flags.padTo > 1048576 {
		return frameInfo{}, nil, fmt.Errorf("image dimensions must be 1..512 and padding 0..1048576")
	}
	if flags.rotate != 0 && flags.rotate != 90 && flags.rotate != 180 && flags.rotate != 270 {
		return frameInfo{}, nil, fmt.Errorf("rotation must be 0, 90, 180 or 270")
	}
	f, err := os.Open(inPath)
	if err != nil {
		return frameInfo{}, nil, err
	}
	defer f.Close()

	img, _, err := image.Decode(f)
	if err != nil {
		return frameInfo{}, nil, err
	}

	sb := img.Bounds()
	resized := imageconv.ResizeCover(img, flags.width, flags.height)
	rotated := imageconv.RotateRGBA(resized, flags.rotate)
	rgb565 := imageconv.EncodeRGB565(rotated, flags.swapBytes)
	padded := imageconv.PadBytes(rgb565, flags.padTo)

	return frameInfo{
		decodedW:    sb.Dx(),
		decodedH:    sb.Dy(),
		rgb565Bytes: len(rgb565),
	}, padded, nil
}

func shortHex(b []byte, max int) string {
	if max <= 0 || len(b) <= max {
		return hex.EncodeToString(b)
	}
	return hex.EncodeToString(b[:max]) + "…"
}

func cmdSyncTime(args []string) error {
	fs := flag.NewFlagSet("sync-time", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	dryRun := fs.Bool("dry-run", false, "do not write config to HID")
	path := fs.String("path", "", "HID path to use (optional)")
	slotOverride := fs.Int("slot", -1, "slot index override (default: read active slot at offset 0)")
	timeoutMS := fs.Int("timeout", 1500, "read timeout (ms)")
	useUTC := fs.Bool("utc", false, "use UTC instead of local time")
	jsonOutput := fs.Bool("json", false, "machine-readable sync result")
	verbose := fs.Bool("verbose", false, "print extra details")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if fs.NArg() != 0 || *timeoutMS < 100 || *timeoutMS > 30000 || *slotOverride < -1 || *slotOverride > 255 {
		return fmt.Errorf("invalid arguments: timeout must be 100..30000 ms; slot must be 0..255")
	}
	release, err := device.AcquireClockLock()
	if err != nil {
		return err
	}
	defer release()
	now := time.Now()
	if *useUTC {
		now = now.UTC()
	}

	if err := device.Init(); err != nil {
		return err
	}
	defer device.Exit()

	all, err := device.Enumerate(vendorID, productID)
	if err != nil {
		return err
	}
	if len(all) == 0 {
		return fmt.Errorf("no CIDOO ABM066 devices found (VID=0x%04x PID=0x%04x)", vendorID, productID)
	}
	screenDevs := device.FilterScreenInterfaces(all)
	if len(screenDevs) == 0 {
		return fmt.Errorf("CIDOO device found, but no screen/config HID interface found (need usagePage=0xff1c usage=0x92); is it connected over USB?")
	}

	var chosen device.Info
	switch {
	case *path != "":
		chosen, err = device.PickByPath(screenDevs, *path)
		if err != nil {
			return err
		}
	case len(screenDevs) == 1:
		chosen = screenDevs[0]
	default:
		fmt.Fprintln(os.Stderr, "Multiple screen/config HID interfaces found. Re-run with --path:")
		for _, d := range screenDevs {
			fmt.Fprintf(os.Stderr, "  %s\n", d.Path)
		}
		return fmt.Errorf("ambiguous device selection")
	}

	dev, err := device.OpenPath(chosen.Path)
	if err != nil {
		return err
	}
	defer dev.Close()

	timeout := time.Duration(*timeoutMS) * time.Millisecond

	slot := *slotOverride
	if slot < 0 {
		b, err := readConfigBytes(dev, 0x0000, 1, timeout)
		if err != nil {
			return err
		}
		if len(b) != 1 {
			return fmt.Errorf("unexpected slot read length: %d", len(b))
		}
		slot = int(b[0])
	}
	if slot < 0 || slot > 255 {
		return fmt.Errorf("invalid slot index: %d", slot)
	}

	baseOff := uint16(slot) * 0x31
	template, err := readConfigBytes(dev, baseOff, protocol.ConfigRecordLen, timeout)
	if err != nil {
		return err
	}
	if len(template) != protocol.ConfigRecordLen {
		return fmt.Errorf("unexpected config record length: %d", len(template))
	}

	if _, err := protocol.ClockDate(template, now.Location()); err != nil {
		return fmt.Errorf("refusing invalid config record: %w", err)
	}
	now = time.Now()
	if *useUTC {
		now = now.UTC()
	}
	updated := make([]byte, len(template))
	copy(updated, template)
	if err := protocol.PatchClockFields(updated, now); err != nil {
		return err
	}

	begin := protocol.NewPacket(protocol.CmdBegin, nil)
	write := protocol.NewWriteConfigPacket(baseOff, updated)
	commit := protocol.NewPacket(protocol.CmdCommit, nil)

	if !*jsonOutput {
		fmt.Printf("Computer time: %s\n", now.Format(time.RFC3339))
		fmt.Printf("HID path: %s\n", chosen.Path)
		fmt.Printf("Slot: %d (base offset 0x%04x)\n", slot, baseOff)
		fmt.Printf("Template clock bytes (35..41): %s\n", hex.EncodeToString(template[35:42]))
		fmt.Printf("Updated  clock bytes (35..41): %s\n", hex.EncodeToString(updated[35:42]))

		if *verbose {
			fmt.Printf("Begin packet:  %s\n", shortHex(begin[:], 32))
			fmt.Printf("Write packet:  %s\n", shortHex(write[:], 32))
			fmt.Printf("Commit packet: %s\n", shortHex(commit[:], 32))
		}

	}
	result := struct {
		Slot      int    `json:"slot"`
		DryRun    bool   `json:"dryRun"`
		Verified  bool   `json:"verified"`
		Timestamp string `json:"timestamp"`
	}{Slot: slot, DryRun: *dryRun, Timestamp: now.Format(time.RFC3339)}
	if *dryRun {
		if *jsonOutput {
			return json.NewEncoder(os.Stdout).Encode(result)
		}
		fmt.Println("Dry run only. Config read requests sent; no config write performed.")
		return nil
	}

	if err := device.WritePacket(dev, begin); err != nil {
		return err
	}
	if err := device.WritePacket(dev, write); err != nil {
		return err
	}
	if err := device.WritePacket(dev, commit); err != nil {
		return err
	}

	readback, err := readConfigBytes(dev, baseOff, protocol.ConfigRecordLen, timeout)
	if err != nil {
		return fmt.Errorf("update sent but readback failed: %w", err)
	}
	if err := protocol.VerifyClockUpdate(template, readback, now); err != nil {
		return fmt.Errorf("update sent but verification failed: %w", err)
	}
	result.Verified = true
	if *jsonOutput {
		return json.NewEncoder(os.Stdout).Encode(result)
	}
	fmt.Println("Clock update verified by reading the configuration back.")
	return nil
}

func readConfigBytes(dev interface {
	Write([]byte) (int, error)
	ReadWithTimeout([]byte, time.Duration) (int, error)
}, offset uint16, length int, timeout time.Duration) ([]byte, error) {
	if length <= 0 {
		return nil, nil
	}

	out := make([]byte, 0, length)
	for i := 0; i < length; i += 4 {
		n := length - i
		if n > 4 {
			n = 4
		}

		p := protocol.NewReadConfigPacket(offset+uint16(i), byte(n))
		if written, err := dev.Write(p[:]); err != nil {
			return nil, err
		} else if written != len(p) {
			return nil, io.ErrShortWrite
		}

		var resp [64]byte
		deadline := time.Now().Add(timeout)
		for {
			remaining := time.Until(deadline)
			if remaining <= 0 {
				return nil, fmt.Errorf("timeout waiting for config response")
			}
			readN, err := dev.ReadWithTimeout(resp[:], remaining)
			if err != nil {
				return nil, err
			}
			if readN < 4 {
				return nil, fmt.Errorf("short response header: %d bytes", readN)
			}
			if resp[0] != protocol.ReportID {
				return nil, fmt.Errorf("unexpected report ID")
			}
			if resp[protocol.CommandOff] != protocol.CmdReadConfig {
				continue
			} // Skip write acknowledgements.
			if readN < 4+n {
				return nil, fmt.Errorf("short config response: %d bytes", readN)
			}
			if readN == len(p) && bytes.Equal(resp[:], p[:]) {
				return nil, fmt.Errorf("refusing echoed config request")
			}
			break
		}

		out = append(out, resp[4:4+n]...)
	}
	return out, nil
}

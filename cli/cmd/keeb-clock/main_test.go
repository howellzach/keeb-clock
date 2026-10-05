package main

import (
	"github.com/howellzach/keeb-clock/internal/protocol"
	"io"
	"testing"
	"time"
)

type fakeHID struct {
	responses [][]byte
	writes    [][]byte
	short     bool
}

func (f *fakeHID) Write(p []byte) (int, error) {
	f.writes = append(f.writes, append([]byte(nil), p...))
	if f.short {
		return 1, nil
	}
	return len(p), nil
}
func (f *fakeHID) ReadWithTimeout(p []byte, _ time.Duration) (int, error) {
	if len(f.responses) == 0 {
		return 0, io.EOF
	}
	r := f.responses[0]
	f.responses = f.responses[1:]
	return copy(p, r), nil
}

func TestReadConfigSkipsWriteAcks(t *testing.T) {
	f := &fakeHID{responses: [][]byte{{4, 0, 0, 2, 0, 0, 0, 0}, {4, 0, 0, 5, 10, 11, 12, 13}, {4, 0, 0, 5, 14, 0, 0, 0}}}
	got, err := readConfigBytes(f, 49, 5, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 5 || got[0] != 10 || got[4] != 14 {
		t.Fatalf("bad read: %v", got)
	}
	if f.writes[0][5] != 49 || f.writes[1][5] != 53 {
		t.Fatal("wrong chunk offsets")
	}
}

func TestReadConfigRejectsMalformedResponses(t *testing.T) {
	echo := protocol.NewReadConfigPacket(0, 4)
	for _, r := range [][]byte{{4, 0}, {4, 0, 0, 5, 1}, {7, 0, 0, 5, 1, 2, 3, 4}, echo[:]} {
		f := &fakeHID{responses: [][]byte{r}}
		if _, err := readConfigBytes(f, 0, 4, time.Second); err == nil {
			t.Fatalf("accepted %v", r)
		}
	}
	f := &fakeHID{short: true}
	if _, err := readConfigBytes(f, 0, 4, time.Second); err != io.ErrShortWrite {
		t.Fatalf("short write: %v", err)
	}
}

func TestInvalidOptionsFailBeforeHID(t *testing.T) {
	for _, args := range [][]string{{"--timeout", "-1"}, {"--timeout", "0"}, {"--slot", "256"}, {"--slot", "-2"}, {"unexpected"}} {
		if err := cmdSyncTime(args); err == nil {
			t.Fatalf("accepted %v", args)
		}
	}
}

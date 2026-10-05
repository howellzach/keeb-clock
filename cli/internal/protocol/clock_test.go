package protocol

import (
	"testing"
	"time"
)

func TestClockPatchPreservesConfig(t *testing.T) {
	before := make([]byte, 48)
	for i := range before {
		before[i] = byte(i)
	}
	after := append([]byte(nil), before...)
	now := time.Date(2026, 10, 5, 14, 23, 45, 0, time.UTC)
	if err := PatchClockFields(after, now); err != nil {
		t.Fatal(err)
	}
	if err := VerifyClockUpdate(before, after, now); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 35; i++ {
		if after[i] != before[i] {
			t.Fatal("config changed")
		}
	}
	after[34]++
	if VerifyClockUpdate(before, after, now) == nil {
		t.Fatal("accepted non-clock change")
	}
}

func TestClockValidation(t *testing.T) {
	now := time.Date(2026, 10, 5, 14, 23, 45, 0, time.UTC)
	valid := make([]byte, 48)
	PatchClockFields(valid, now)
	for _, tc := range []struct {
		name   string
		offset int
		value  byte
	}{
		{"BCD", 35, 0xfa}, {"seconds", 35, 0x60}, {"hours", 37, 0x24},
		{"weekday", 38, 7}, {"day", 39, 0}, {"month", 40, 0x13},
	} {
		t.Run(tc.name, func(t *testing.T) {
			record := append([]byte(nil), valid...)
			record[tc.offset] = tc.value
			if _, err := ClockDate(record, time.UTC); err == nil {
				t.Fatal("accepted invalid clock")
			}
		})
	}
	valid[39] = 0x31
	valid[40] = 0x02
	if _, err := ClockDate(valid, time.UTC); err == nil {
		t.Fatal("accepted February 31")
	}
	if _, err := ClockDate(make([]byte, 48), time.UTC); err == nil {
		t.Fatal("accepted zero record")
	}
}

func TestReadbackAcrossMidnight(t *testing.T) {
	now := time.Date(2026, 12, 31, 23, 59, 59, 0, time.UTC)
	before := make([]byte, 48)
	after := make([]byte, 48)
	PatchClockFields(after, now.Add(2*time.Second))
	if err := VerifyClockUpdate(before, after, now); err != nil {
		t.Fatal(err)
	}
	PatchClockFields(after, now.Add(6*time.Second))
	if VerifyClockUpdate(before, after, now) == nil {
		t.Fatal("accepted stale/far clock")
	}
}

package protocol

import (
	"fmt"
	"time"
)

// ClockDate rejects invalid BCD and normalized/impossible calendar dates.
func ClockDate(record []byte, location *time.Location) (time.Time, error) {
	if len(record) != ConfigRecordLen {
		return time.Time{}, fmt.Errorf("invalid config length: %d", len(record))
	}
	values := make([]int, 7)
	for i, b := range record[35:42] {
		if i == 3 {
			values[i] = int(b)
			continue
		}
		if b&15 > 9 || b>>4 > 9 {
			return time.Time{}, fmt.Errorf("invalid BCD clock byte at %d", i+35)
		}
		values[i] = int(b>>4)*10 + int(b&15)
	}
	s, m, h, w, d, month, y := values[0], values[1], values[2], values[3], values[4], values[5], values[6]
	if s > 59 || m > 59 || h > 23 || w > 6 || d < 1 || d > 31 || month < 1 || month > 12 {
		return time.Time{}, fmt.Errorf("invalid config clock fields")
	}
	date := time.Date(2000+y, time.Month(month), d, h, m, s, 0, location)
	if date.Day() != d || int(date.Month()) != month {
		return time.Time{}, fmt.Errorf("invalid config calendar date")
	}
	return date, nil
}

func VerifyClockUpdate(before, after []byte, expected time.Time) error {
	if len(before) != ConfigRecordLen || len(after) != ConfigRecordLen {
		return fmt.Errorf("invalid config record length")
	}
	for i := range before {
		if (i < 35 || i > 41) && before[i] != after[i] {
			return fmt.Errorf("non-clock config byte %d changed", i)
		}
	}
	actual, err := ClockDate(after, expected.Location())
	if err != nil {
		return err
	}
	delta := actual.Sub(expected.Truncate(time.Second))
	if delta < 0 || delta > 5*time.Second {
		return fmt.Errorf("clock readback does not match requested time")
	}
	if after[38] != byte(actual.Weekday()) {
		return fmt.Errorf("clock readback weekday mismatch")
	}
	return nil
}

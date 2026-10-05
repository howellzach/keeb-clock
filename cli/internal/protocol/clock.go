package protocol

import (
	"fmt"
	"time"
)

const ConfigRecordLen = 48

func PatchClockFields(record []byte, t time.Time) error {
	if len(record) < ConfigRecordLen {
		return fmt.Errorf("config record too small: %d", len(record))
	}

	// Offsets 35..41 per protocol notes.
	record[35] = toBCD(byte(t.Second()))
	record[36] = toBCD(byte(t.Minute()))
	record[37] = toBCD(byte(t.Hour()))
	record[38] = byte(t.Weekday()) // Sunday=0..Saturday=6
	record[39] = toBCD(byte(t.Day()))
	record[40] = toBCD(byte(t.Month()))
	record[41] = toBCD(byte(t.Year() % 100))
	return nil
}

func toBCD(v byte) byte {
	return ((v / 10) << 4) | (v % 10)
}

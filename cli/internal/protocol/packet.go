package protocol

const (
	ReportSize = 64
	ReportID   = byte(0x04)

	ChecksumLo = 1
	ChecksumHi = 2
	CommandOff = 3

	PayloadOff      = 4
	MaxPayloadSize  = ReportSize - PayloadOff
	ChunkPayloadOff = 8
	ChunkPayloadMax = ReportSize - ChunkPayloadOff
)

type Packet [ReportSize]byte

func NewPacket(command byte, payload []byte) Packet {
	var p Packet
	p[0] = ReportID
	p[CommandOff] = command

	if len(payload) > MaxPayloadSize {
		payload = payload[:MaxPayloadSize]
	}
	copy(p[PayloadOff:], payload)

	sum := checksum16(p[CommandOff:])
	p[ChecksumLo] = byte(sum)
	p[ChecksumHi] = byte(sum >> 8)
	return p
}

func checksum16(data []byte) uint16 {
	var sum uint32
	for _, b := range data {
		sum += uint32(b)
	}
	return uint16(sum & 0xffff)
}

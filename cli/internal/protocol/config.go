package protocol

const (
	CmdReadConfig  = byte(0x05)
	CmdWriteConfig = byte(0x06)
)

func NewReadConfigPacket(offset uint16, length byte) Packet {
	var p Packet
	p[0] = ReportID
	p[CommandOff] = CmdReadConfig
	p[4] = length
	p[5] = byte(offset)
	p[6] = byte(offset >> 8)
	p[7] = 0x00

	sum := checksum16(p[CommandOff:])
	p[ChecksumLo] = byte(sum)
	p[ChecksumHi] = byte(sum >> 8)
	return p
}

func NewWriteConfigPacket(offset uint16, chunk []byte) Packet {
	var p Packet
	p[0] = ReportID
	p[CommandOff] = CmdWriteConfig

	if len(chunk) > ChunkPayloadMax {
		chunk = chunk[:ChunkPayloadMax]
	}

	p[4] = byte(len(chunk))
	p[5] = byte(offset)
	p[6] = byte(offset >> 8)
	p[7] = 0x00
	copy(p[ChunkPayloadOff:], chunk)

	sum := checksum16(p[CommandOff:])
	p[ChecksumLo] = byte(sum)
	p[ChecksumHi] = byte(sum >> 8)
	return p
}

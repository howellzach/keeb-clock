package protocol

const (
	CmdBegin  = byte(0x01)
	CmdChunk  = byte(0x21)
	CmdCommit = byte(0x02)
)

func BuildImageUploadPackets(frame []byte) []Packet {
	packets := make([]Packet, 0, 2+(len(frame)+MaxPayloadSize-1)/MaxPayloadSize)
	packets = append(packets, NewPacket(CmdBegin, nil))

	for off := 0; off < len(frame); off += MaxPayloadSize {
		end := off + MaxPayloadSize
		if end > len(frame) {
			end = len(frame)
		}
		packets = append(packets, NewPacket(CmdChunk, frame[off:end]))
	}

	packets = append(packets, NewPacket(CmdCommit, nil))
	return packets
}

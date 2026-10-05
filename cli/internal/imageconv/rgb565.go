package imageconv

import (
	"image"
	"image/color"
)

func RGB565(c color.Color) (hi, lo byte) {
	r16, g16, b16, _ := c.RGBA()

	r := uint16(r16 >> 11) // 5 bits
	g := uint16(g16 >> 10) // 6 bits
	b := uint16(b16 >> 11) // 5 bits

	v := (r << 11) | (g << 5) | b
	return byte(v >> 8), byte(v)
}

func EncodeRGB565(img image.Image, swapBytes bool) []byte {
	b := img.Bounds()
	out := make([]byte, 0, b.Dx()*b.Dy()*2)

	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			hi, lo := RGB565(img.At(x, y))
			if swapBytes {
				out = append(out, lo, hi)
			} else {
				out = append(out, hi, lo)
			}
		}
	}
	return out
}

func PadBytes(in []byte, padTo int) []byte {
	if padTo <= 0 || len(in) >= padTo {
		return in
	}
	out := make([]byte, padTo)
	copy(out, in)
	return out
}

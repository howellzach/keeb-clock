package imageconv

import (
	"image"
	"image/draw"
)

// ResizeCover scales src to fill width x height and then center-crops.
func ResizeCover(src image.Image, width, height int) *image.RGBA {
	if width <= 0 || height <= 0 {
		return image.NewRGBA(image.Rect(0, 0, 0, 0))
	}

	sb := src.Bounds()
	sw, sh := sb.Dx(), sb.Dy()
	if sw <= 0 || sh <= 0 {
		return image.NewRGBA(image.Rect(0, 0, width, height))
	}

	scaleX := float64(width) / float64(sw)
	scaleY := float64(height) / float64(sh)
	scale := scaleX
	if scaleY > scaleX {
		scale = scaleY
	}

	tw := int(float64(sw)*scale + 0.5)
	th := int(float64(sh)*scale + 0.5)
	if tw < 1 {
		tw = 1
	}
	if th < 1 {
		th = 1
	}

	tmp := image.NewRGBA(image.Rect(0, 0, tw, th))
	scaleNearest(tmp, src)

	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	offX := (tw - width) / 2
	offY := (th - height) / 2
	draw.Draw(dst, dst.Bounds(), tmp, image.Pt(offX, offY), draw.Src)
	return dst
}

func scaleNearest(dst *image.RGBA, src image.Image) {
	db := dst.Bounds()
	sb := src.Bounds()
	sw, sh := sb.Dx(), sb.Dy()
	dw, dh := db.Dx(), db.Dy()
	if sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 {
		return
	}

	for y := 0; y < dh; y++ {
		sy := sb.Min.Y + (y*sh)/dh
		for x := 0; x < dw; x++ {
			sx := sb.Min.X + (x*sw)/dw
			dst.Set(x, y, src.At(sx, sy))
		}
	}
}

func RotateRGBA(src *image.RGBA, degrees int) *image.RGBA {
	d := ((degrees % 360) + 360) % 360
	if d == 0 {
		return src
	}

	sb := src.Bounds()
	w, h := sb.Dx(), sb.Dy()

	switch d {
	case 90:
		dst := image.NewRGBA(image.Rect(0, 0, h, w))
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				dst.SetRGBA(h-1-y, x, src.RGBAAt(x, y))
			}
		}
		return dst
	case 180:
		dst := image.NewRGBA(image.Rect(0, 0, w, h))
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				dst.SetRGBA(w-1-x, h-1-y, src.RGBAAt(x, y))
			}
		}
		return dst
	case 270:
		dst := image.NewRGBA(image.Rect(0, 0, h, w))
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				dst.SetRGBA(y, w-1-x, src.RGBAAt(x, y))
			}
		}
		return dst
	default:
		return src
	}
}

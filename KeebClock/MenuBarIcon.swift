import AppKit

/// Clock-keycap template image for the menu bar.
@MainActor
enum MenuBarIcon {
  static let image: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()

      let keycap = NSBezierPath()
      keycap.move(to: NSPoint(x: 4, y: 16))
      keycap.line(to: NSPoint(x: 14, y: 16))
      keycap.curve(to: NSPoint(x: 16, y: 14), controlPoint1: NSPoint(x: 15.2, y: 16), controlPoint2: NSPoint(x: 15.8, y: 15.3))
      keycap.line(to: NSPoint(x: 16.7, y: 4))
      keycap.curve(to: NSPoint(x: 14.5, y: 2), controlPoint1: NSPoint(x: 16.8, y: 2.7), controlPoint2: NSPoint(x: 16, y: 2))
      keycap.line(to: NSPoint(x: 3.5, y: 2))
      keycap.curve(to: NSPoint(x: 1.3, y: 4), controlPoint1: NSPoint(x: 2, y: 2), controlPoint2: NSPoint(x: 1.2, y: 2.7))
      keycap.line(to: NSPoint(x: 2, y: 14))
      keycap.curve(to: NSPoint(x: 4, y: 16), controlPoint1: NSPoint(x: 2.2, y: 15.3), controlPoint2: NSPoint(x: 2.8, y: 16))
      keycap.close()
      keycap.lineWidth = 1.2
      keycap.lineJoinStyle = .round
      keycap.stroke()

      let bevel = NSBezierPath()
      bevel.move(to: NSPoint(x: 3.5, y: 4.2))
      bevel.line(to: NSPoint(x: 14.5, y: 4.2))
      bevel.lineWidth = 1
      bevel.lineCapStyle = .round
      bevel.stroke()

      let clock = NSBezierPath(ovalIn: NSRect(x: 4.8, y: 6.1, width: 8.4, height: 8.4))
      clock.lineWidth = 1.1
      clock.stroke()
      let hands = NSBezierPath()
      hands.move(to: NSPoint(x: 6.5, y: 11.8))
      hands.line(to: NSPoint(x: 9, y: 10.3))
      hands.line(to: NSPoint(x: 11.8, y: 12.6))
      hands.lineWidth = 1.35
      hands.lineCapStyle = .round
      hands.lineJoinStyle = .round
      hands.stroke()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Keeb Clock"
    return image
  }()
}

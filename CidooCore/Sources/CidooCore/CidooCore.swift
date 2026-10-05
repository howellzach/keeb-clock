import Foundation
import Darwin
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

public enum CidooCoreError: Error, CustomStringConvertible {
  case noDeviceFound
  case noScreenInterface
  case ambiguousDevice([UInt64])
  case deviceNotFound(UInt64)
  case accessDenied(Int32, operation: String = "Accessing the keyboard")
  case deviceBusy
  case io(String)
  case protocolError(String)

  public var description: String {
    switch self {
    case .noDeviceFound:
      return "no CIDOO ABM066 devices found"
    case .noScreenInterface:
      return
        "CIDOO device found, but no screen/config HID interface found (need usagePage=0xff1c usage=0x92); is it connected over USB?"
    case .ambiguousDevice(let ids):
      return
        "multiple screen/config HID interfaces found; specify one: \(ids.map(String.init).joined(separator: ", "))"
    case .deviceNotFound(let id):
      return "no screen/config HID device with registry id \(id)"
    case .accessDenied(let code, let operation):
      return "macOS denied keyboard access while \(operation.lowercased()) (code \(code)). Check Privacy & Security → Input Monitoring if this app is listed, then quit and reopen it. On a managed Mac, ask your administrator to approve the app and its device access."
    case .deviceBusy:
      return "Another app has exclusive access to the keyboard. Close other keyboard configuration tools, then try Sync now."
    case .io(let msg):
      return msg
    case .protocolError(let msg):
      return msg
    }
  }
}

extension CidooCoreError {
  public var isAccessDenied: Bool {
    if case .accessDenied = self { return true }
    return false
  }
}

// Only identify permission errors when IOKit explicitly reports denial.
func hidFailure(operation: String, code: IOReturn) -> CidooCoreError {
  switch code {
  case kIOReturnNotPermitted, kIOReturnNotPrivileged: return .accessDenied(code, operation: operation)
  case kIOReturnExclusiveAccess: return .deviceBusy
  default: return .io("\(operation) failed (code \(code)). Reconnect the USB cable and try Sync now. If it persists, include this code in your issue report.")
  }
}

public struct HIDInterfaceInfo {
  public let registryID: UInt64
  public let manufacturer: String?
  public let product: String?
  public let interface: Int
  public let usagePage: Int
  public let usage: Int

  // IOHIDDevice is not Sendable; keep it internal.
  internal let device: IOHIDDevice
}

public struct CidooConstants {
  public static let vendorID: Int = 0x320f
  public static let productID: Int = 0x5055

  public static let usagePageScreen: Int = 0xff1c
  public static let usageScreen: Int = 0x0092

  public static let reportID: UInt8 = 0x04
  public static let reportSize = 64

  public static let cmdBegin: UInt8 = 0x01
  public static let cmdCommit: UInt8 = 0x02
  public static let cmdReadConfig: UInt8 = 0x05
  public static let cmdWriteConfig: UInt8 = 0x06

  public static let configRecordLen = 48
}

public struct SyncResult: Sendable {
  public let verified: Bool
  public let registryID: UInt64
  public let slot: Int
  public let baseOffset: UInt16
  public let templateClockHex: String
  public let updatedClockHex: String
  public let timestampRFC3339: String
}

public enum CidooCore {
  public static func enumerateInterfaces() throws -> [HIDInterfaceInfo] {
    // Discovery must not open the typing interfaces. Independent devices also
    // remain valid after this short-lived manager is released.
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault,
      IOOptionBits(IOHIDManagerOptions.independentDevices.rawValue))
    let match: [String: Any] = [
      kIOHIDVendorIDKey as String: CidooConstants.vendorID,
      kIOHIDProductIDKey as String: CidooConstants.productID,
    ]
    IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)

    guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
      return []
    }

    var out: [HIDInterfaceInfo] = []
    for dev in set {
      let usagePage =
        (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue
        ?? -1
      let usage =
        (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue
        ?? -1

      var registryID: UInt64 = 0
      let service = IOHIDDeviceGetService(dev)
      if service != 0 {
        _ = IORegistryEntryGetRegistryEntryID(service, &registryID)
      }

      let manufacturer = IOHIDDeviceGetProperty(dev, kIOHIDManufacturerKey as CFString) as? String
      let product = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String
      let interface =
        (IOHIDDeviceGetProperty(dev, kIOHIDInterfaceIDKey as CFString) as? NSNumber)?.intValue ?? -1

      out.append(
        HIDInterfaceInfo(
          registryID: registryID,
          manufacturer: manufacturer,
          product: product,
          interface: interface,
          usagePage: usagePage,
          usage: usage,
          device: dev
        )
      )
    }
    return out
  }

  public static func syncTime(
    dryRun: Bool = false,
    utc: Bool = false,
    timeoutMS: Int = 1500,
    slotOverride: Int? = nil,
    registryIDOverride: UInt64? = nil
  ) throws -> SyncResult {
    guard (100...30000).contains(timeoutMS), slotOverride.map({ (0...255).contains($0) }) ?? true else {
      throw CidooCoreError.protocolError("Invalid timeout or config slot.")
    }
    let transactionLock = try ClockSyncLock()
    defer { transactionLock.release() }
    let all = try enumerateInterfaces()
    if all.isEmpty { throw CidooCoreError.noDeviceFound }

    let screen = all.filter {
      $0.usagePage == CidooConstants.usagePageScreen && $0.usage == CidooConstants.usageScreen
    }
    if screen.isEmpty { throw CidooCoreError.noScreenInterface }

    let chosen: HIDInterfaceInfo
    if let rid = registryIDOverride {
      guard let d = screen.first(where: { $0.registryID == rid }) else {
        throw CidooCoreError.deviceNotFound(rid)
      }
      chosen = d
    } else if screen.count == 1 {
      chosen = screen[0]
    } else {
      throw CidooCoreError.ambiguousDevice(screen.map(\.registryID).sorted())
    }

    let hid = HIDDeviceIO(device: chosen.device)
    try hid.open()
    defer { hid.close() }

    return try performSync(hid: hid, registryID: chosen.registryID, dryRun: dryRun,
      utc: utc, timeoutMS: timeoutMS, slotOverride: slotOverride)
  }
}

// Transport boundary lets tests exercise real packet/transaction logic without USB.
protocol ClockTransport {
  func writeOutputReport(reportID: UInt8, bytes: [UInt8]) throws
  func readInputReport(timeout: TimeInterval) throws -> [UInt8]
}

func performSync(hid: any ClockTransport, registryID: UInt64 = 0, dryRun: Bool,
  utc: Bool, timeoutMS: Int = 1500, slotOverride: Int? = nil,
  dateProvider: () -> Date = { Date() }) throws -> SyncResult {
    let timeout = TimeInterval(timeoutMS) / 1000

    let slot: Int
    if let s = slotOverride {
      slot = s
    } else {
      let b = try readConfig(hid: hid, offset: 0x0000, length: 1, timeout: timeout)
      guard b.count == 1 else {
        throw CidooCoreError.protocolError("unexpected slot read length: \(b.count)")
      }
      slot = Int(b[0])
    }

    guard slot >= 0 && slot <= 255 else {
      throw CidooCoreError.protocolError("invalid slot index: \(slot)")
    }
    let baseOff = UInt16(slot) &* 0x31

    let template = try readConfig(
      hid: hid, offset: baseOff, length: CidooConstants.configRecordLen, timeout: timeout)
    guard template.count == CidooConstants.configRecordLen else {
      throw CidooCoreError.protocolError("unexpected config record length: \(template.count)")
    }

    _ = try clockDate(template)
    let now = dateProvider()
    var updated = template
    try patchClockFields(record: &updated, date: now, utc: utc)

    let begin = newPacket(command: CidooConstants.cmdBegin, payload: [])
    let write = newWriteConfigPacket(offset: baseOff, chunk: updated)
    let commit = newPacket(command: CidooConstants.cmdCommit, payload: [])

    if !dryRun {
      try hid.writeOutputReport(reportID: CidooConstants.reportID, bytes: begin)
      try hid.writeOutputReport(reportID: CidooConstants.reportID, bytes: write)
      try hid.writeOutputReport(reportID: CidooConstants.reportID, bytes: commit)
      do {
        let readback = try readConfig(hid: hid, offset: baseOff, length: 48, timeout: timeout)
        try verifyClockUpdate(before: template, requested: updated, actual: readback)
      } catch {
        throw CidooCoreError.protocolError("Update sent, but readback verification failed: \(error)")
      }
    }

    return SyncResult(
      verified: !dryRun,
      registryID: registryID,
      slot: slot,
      baseOffset: baseOff,
      templateClockHex: hex(template[35..<42]),
      updatedClockHex: hex(updated[35..<42]),
      timestampRFC3339: formatRFC3339(now, utc: utc)
    )
}


// MARK: - HID I/O

final class HIDDeviceIO: ClockTransport {
  private let device: IOHIDDevice
  private var opened = false
  private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
  private let lock = NSLock()
  private var reports: [[UInt8]] = []
  private var inputError: String?

  init(device: IOHIDDevice) { self.device = device }
  deinit { inputBuffer.deallocate() }

  func open() throws {
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else { throw hidFailure(operation: "Opening the screen interface", code: result) }
    opened = true
    IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64,
      { context, result, _, _, reportID, report, length in
        guard let context else { return }
        let owner = Unmanaged<HIDDeviceIO>.fromOpaque(context).takeUnretainedValue()
        owner.lock.lock()
        defer { owner.lock.unlock() }
        guard result == kIOReturnSuccess, length > 0, length <= 64 else {
          owner.inputError = "Invalid HID input report: status \(result), length \(length)"
          return
        }
        var bytes = Array(UnsafeBufferPointer(start: report, count: length))
        if bytes.first != CidooConstants.reportID && reportID == UInt32(CidooConstants.reportID) {
          bytes.insert(CidooConstants.reportID, at: 0)
        }
        guard owner.reports.count < 64 else {
          owner.inputError = "Too many queued keyboard reports."
          return
        }
        owner.reports.append(bytes)
      }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
  }

  func close() {
    guard opened else { return }
    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, nil, nil)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    opened = false
  }

  func writeOutputReport(reportID: UInt8, bytes: [UInt8]) throws {
    guard bytes.count == 64 else { throw CidooCoreError.io("Invalid HID output report length.") }
    let result = bytes.withUnsafeBufferPointer {
      IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), $0.baseAddress!, $0.count)
    }
    guard result == kIOReturnSuccess else { throw hidFailure(operation: "Sending the clock update", code: result) }
  }

  func readInputReport(timeout: TimeInterval) throws -> [UInt8] {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, timeout) * 1_000_000_000)
    while DispatchTime.now().uptimeNanoseconds < deadline {
      lock.lock()
      let error = inputError
      let report = reports.isEmpty ? nil : reports.removeFirst()
      lock.unlock()
      if let error { throw CidooCoreError.io(error) }
      if let report { return report }
      CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.005, false)
    }
    throw CidooCoreError.io("Timeout waiting for keyboard response.")
  }
}

// MARK: - Protocol

private let checksumLoOff = 1
private let checksumHiOff = 2
private let commandOff = 3
private let chunkPayloadOff = 8

func newPacket(command: UInt8, payload: [UInt8]) -> [UInt8] {
  var p = [UInt8](repeating: 0, count: CidooConstants.reportSize)
  p[0] = CidooConstants.reportID
  p[commandOff] = command

  let payloadOff = 4
  let maxPayload = CidooConstants.reportSize - payloadOff
  let n = min(payload.count, maxPayload)
  if n > 0 {
    p.replaceSubrange(payloadOff..<(payloadOff + n), with: payload.prefix(n))
  }

  let sum = checksum16(p[commandOff...])
  p[checksumLoOff] = UInt8(sum & 0xff)
  p[checksumHiOff] = UInt8((sum >> 8) & 0xff)
  return p
}

func newReadConfigPacket(offset: UInt16, length: UInt8) -> [UInt8] {
  var p = [UInt8](repeating: 0, count: CidooConstants.reportSize)
  p[0] = CidooConstants.reportID
  p[commandOff] = CidooConstants.cmdReadConfig
  p[4] = length
  p[5] = UInt8(offset & 0xff)
  p[6] = UInt8((offset >> 8) & 0xff)
  p[7] = 0x00
  let sum = checksum16(p[commandOff...])
  p[checksumLoOff] = UInt8(sum & 0xff)
  p[checksumHiOff] = UInt8((sum >> 8) & 0xff)
  return p
}

func newWriteConfigPacket(offset: UInt16, chunk: [UInt8]) -> [UInt8] {
  var p = [UInt8](repeating: 0, count: CidooConstants.reportSize)
  p[0] = CidooConstants.reportID
  p[commandOff] = CidooConstants.cmdWriteConfig

  let max = CidooConstants.reportSize - chunkPayloadOff
  let n = min(chunk.count, max)
  p[4] = UInt8(n)
  p[5] = UInt8(offset & 0xff)
  p[6] = UInt8((offset >> 8) & 0xff)
  p[7] = 0x00
  if n > 0 {
    p.replaceSubrange(chunkPayloadOff..<(chunkPayloadOff + n), with: chunk.prefix(n))
  }

  let sum = checksum16(p[commandOff...])
  p[checksumLoOff] = UInt8(sum & 0xff)
  p[checksumHiOff] = UInt8((sum >> 8) & 0xff)
  return p
}

func checksum16(_ bytes: ArraySlice<UInt8>) -> UInt16 {
  var sum: UInt32 = 0
  for b in bytes { sum += UInt32(b) }
  return UInt16(sum & 0xffff)
}

func readConfig(hid: any ClockTransport, offset: UInt16, length: Int,
  timeout: TimeInterval) throws -> [UInt8] {
  guard length > 0, Int(offset) + length <= 65536 else {
    throw CidooCoreError.protocolError("Invalid config read range.")
  }
  var output: [UInt8] = []
  while output.count < length {
    let count = min(4, length - output.count)
    let request = newReadConfigPacket(offset: offset + UInt16(output.count), length: UInt8(count))
    try hid.writeOutputReport(reportID: CidooConstants.reportID, bytes: request)
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
    while true {
      let current = DispatchTime.now().uptimeNanoseconds
      guard current < deadline else { throw CidooCoreError.io("Timeout waiting for config response.") }
      let response = try hid.readInputReport(timeout: Double(deadline - current) / 1_000_000_000)
      guard response.count >= 4, response[0] == CidooConstants.reportID else {
        throw CidooCoreError.protocolError("Invalid keyboard response header.")
      }
      if response[3] != CidooConstants.cmdReadConfig { continue }
      guard response.count >= 4 + count, response.count <= 64, response != request else {
        throw CidooCoreError.protocolError("Short or echoed config response.")
      }
      output.append(contentsOf: response[4..<(4 + count)])
      break
    }
  }
  return output
}

func patchClockFields(record: inout [UInt8], date: Date, utc: Bool) throws {
  guard record.count >= CidooConstants.configRecordLen else {
    throw CidooCoreError.protocolError("config record too small: \(record.count)")
  }

  var cal = Calendar(identifier: .gregorian)
  if utc { cal.timeZone = TimeZone(secondsFromGMT: 0)! }
  let comps = cal.dateComponents(
    [.year, .month, .day, .hour, .minute, .second, .weekday], from: date)

  guard
    let year = comps.year,
    let month = comps.month,
    let day = comps.day,
    let hour = comps.hour,
    let minute = comps.minute,
    let second = comps.second,
    let weekdayApple = comps.weekday
  else {
    throw CidooCoreError.protocolError("failed to compute date components")
  }

  let weekday = UInt8((weekdayApple - 1) & 0x7)  // Sunday=0..Saturday=6

  record[35] = toBCD(UInt8(second))
  record[36] = toBCD(UInt8(minute))
  record[37] = toBCD(UInt8(hour))
  record[38] = weekday
  record[39] = toBCD(UInt8(day))
  record[40] = toBCD(UInt8(month))
  record[41] = toBCD(UInt8(year % 100))
}

func toBCD(_ v: UInt8) -> UInt8 {
  ((v / 10) << 4) | (v % 10)
}

// MARK: - Formatting

func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
  bytes.map { String(format: "%02x", $0) }.joined()
}

func formatRFC3339(_ date: Date, utc: Bool) -> String {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime]
  f.timeZone = utc ? TimeZone(secondsFromGMT: 0)! : TimeZone.current
  return f.string(from: date)
}

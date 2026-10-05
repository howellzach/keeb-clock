import XCTest
@testable import CidooCore

final class FakeTransport: ClockTransport {
  var record: [UInt8]
  var reports: [[UInt8]] = []
  var commands: [UInt8] = []
  var corruptReadback = false
  var ignoreWrite = false
  var failedCommand: UInt8?

  init(record: [UInt8]) { self.record = record }

  func writeOutputReport(reportID: UInt8, bytes: [UInt8]) throws {
    commands.append(bytes[3])
    if bytes[3] == failedCommand { throw CidooCoreError.io("Simulated write failure") }
    if bytes[3] == 5 {
      let offset = Int(bytes[5]) + Int(bytes[6]) * 256
      let count = Int(bytes[4])
      let payload = count == 1 && offset == 0 ? [UInt8(0)] : Array(record[offset..<(offset+count)])
      reports.append([4, 0, 0, 5] + payload)
    } else {
      if bytes[3] == 6 && !ignoreWrite { record = Array(bytes[8..<56]) }
      if bytes[3] == 2 && corruptReadback { record[34] ^= 1 }
      reports.append([4, 0, 0, bytes[3], 0, 0, 0, 0])
    }
  }

  func readInputReport(timeout: TimeInterval) throws -> [UInt8] {
    guard !reports.isEmpty else { throw CidooCoreError.io("Simulated timeout") }
    return reports.removeFirst()
  }
}

final class CidooCoreTests: XCTestCase {
  let now = ISO8601DateFormatter().date(from: "2026-10-05T14:23:45Z")!

  func validRecord(date: Date? = nil) throws -> [UInt8] {
    var record = (0..<48).map { UInt8($0) }
    try patchClockFields(record: &record, date: date ?? now, utc: true)
    return record
  }

  func testPacketMatchesKnownWireLayout() {
    let packet = newReadConfigPacket(offset: 49, length: 4)
    XCTAssertEqual(Array(packet.prefix(8)), [4, 58, 0, 5, 4, 49, 0, 0])
    XCTAssertEqual(packet.count, 64)
  }

  func testDryRunReadsOnly() throws {
    let fake = FakeTransport(record: try validRecord())
    let result = try performSync(hid: fake, dryRun: true, utc: true, dateProvider: { self.now })
    XCTAssertFalse(result.verified)
    XCTAssertEqual(result.slot, 0)
    XCTAssertEqual(fake.commands, [UInt8](repeating: 5, count: 13))
  }

  func testUpdateReadsBackAndPreservesConfiguration() throws {
    let before = try validRecord(date: now.addingTimeInterval(-3600))
    let fake = FakeTransport(record: before)
    let result = try performSync(hid: fake, dryRun: false, utc: true, dateProvider: { self.now })
    XCTAssertTrue(result.verified)
    XCTAssertEqual(Array(fake.commands[13..<16]), [1, 6, 2])
    XCTAssertEqual(fake.commands.count, 28)
    try verifyClockUpdate(before: before, requested: fake.record, actual: fake.record)
  }

  func testRejectsNonClockReadbackChange() throws {
    let fake = FakeTransport(record: try validRecord())
    fake.corruptReadback = true
    XCTAssertThrowsError(try performSync(hid: fake, dryRun: false, utc: true))
  }

  func testRejectsUnacceptedClockWrite() throws {
    let fake = FakeTransport(record: try validRecord(date: now.addingTimeInterval(-3600)))
    fake.ignoreWrite = true
    XCTAssertThrowsError(try performSync(hid: fake, dryRun: false, utc: true, dateProvider: { self.now }))
  }

  func testWriteFailureDoesNotCommit() throws {
    let fake = FakeTransport(record: try validRecord())
    fake.failedCommand = 6
    XCTAssertThrowsError(try performSync(hid: fake, dryRun: false, utc: true))
    XCTAssertFalse(fake.commands.contains(2))
  }

  func testMalformedRecordsNeverWrite() throws {
    for (offset, byte) in [(35, UInt8(0xfa)), (35, 0x60), (37, 0x24), (38, 7), (39, 0), (40, 0x13)] {
      var record = try validRecord()
      record[offset] = byte
      let fake = FakeTransport(record: record)
      XCTAssertThrowsError(try performSync(hid: fake, dryRun: false, utc: true))
      XCTAssertFalse(fake.commands.contains(1))
    }
    XCTAssertThrowsError(try clockDate([UInt8](repeating: 0, count: 48)))
    var impossible = try validRecord()
    impossible[39] = 0x31; impossible[40] = 0x02
    XCTAssertThrowsError(try clockDate(impossible))
  }

  func testReadRejectsShortWrongAndEchoedReports() throws {
    for report in [[4, 0], [4, 0, 0, 5, 1], [7, 0, 0, 5, 1, 2, 3, 4], newReadConfigPacket(offset: 0, length: 4)] {
      let fake = FakeTransport(record: try validRecord())
      fake.reports = [report]
      XCTAssertThrowsError(try readConfig(hid: fake, offset: 0, length: 4, timeout: 1))
    }
  }

  func testReadbackAcrossMidnightAndTimeTolerance() throws {
    let midnight = ISO8601DateFormatter().date(from: "2026-12-31T23:59:59Z")!
    let before = try validRecord()
    let requested = try validRecord(date: midnight)
    try verifyClockUpdate(before: before, requested: requested, actual: validRecord(date: midnight.addingTimeInterval(2)))
    XCTAssertThrowsError(try verifyClockUpdate(before: before, requested: requested, actual: validRecord(date: midnight.addingTimeInterval(6))))
    XCTAssertThrowsError(try verifyClockUpdate(before: before, requested: requested, actual: validRecord(date: midnight.addingTimeInterval(-1))))
  }

  func testUTCAndLocalClockEncoding() throws {
    let utc = try validRecord()
    XCTAssertEqual(Array(utc[35..<42]), [0x45, 0x23, 0x14, 1, 0x05, 0x10, 0x26])
    var local = utc
    try patchClockFields(record: &local, date: now, utc: false)
    let calendar = Calendar(identifier: .gregorian)
    XCTAssertEqual(local[37], toBCD(UInt8(calendar.component(.hour, from: now))))
    XCTAssertEqual(local[39], toBCD(UInt8(calendar.component(.day, from: now))))
  }

  func testProcessLockRejectsOverlapAndReleases() throws {
    let first = try ClockSyncLock()
    XCTAssertThrowsError(try ClockSyncLock())
    first.release()
    let second = try ClockSyncLock()
    second.release()
  }

  func testOptionsRejectedBeforeAccessingDevice() {
    XCTAssertThrowsError(try CidooCore.syncTime(timeoutMS: 0))
    XCTAssertThrowsError(try CidooCore.syncTime(slotOverride: 256))
    XCTAssertThrowsError(try CidooCore.syncTime(slotOverride: -1))
  }

  func testLiveKeyboardWhenExplicitlyRequested() throws {
    let mode = ProcessInfo.processInfo.environment["CIDOO_LIVE_TEST"]
    guard mode == "read" || mode == "write" else {
      throw XCTSkip("Live USB test requires CIDOO_LIVE_TEST=read or write.")
    }
    let result = try CidooCore.syncTime(dryRun: mode == "read")
    XCTAssertEqual(result.verified, mode == "write")
    print("Direct Swift HID: slot \(result.slot), verified \(result.verified), clock \(result.updatedClockHex)")
  }
}

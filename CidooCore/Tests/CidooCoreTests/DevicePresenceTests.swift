import XCTest
import IOKit
import IOKit.hid
@testable import CidooCore

final class DevicePresenceTests: XCTestCase {
  func testUnplugImmediatelyInvalidatesVerifiedResult() {
    var presence = DevicePresence()
    presence.update([100])
    let generation = presence.generation
    XCTAssertTrue(presence.acceptsResult(from: generation))
    presence.update([])
    XCTAssertEqual(presence.isConnected, false)
    XCTAssertFalse(presence.acceptsResult(from: generation))
  }

  func testRapidReplugCannotAcceptThePreviousDevicesSyncResult() {
    var presence = DevicePresence()
    presence.update([100])
    let generation = presence.generation
    presence.update([])
    presence.update([101])
    XCTAssertEqual(presence.isConnected, true)
    XCTAssertFalse(presence.acceptsResult(from: generation))
    XCTAssertTrue(presence.acceptsResult(from: presence.generation))
  }

  func testDuplicateNotificationsDoNotInvalidateOrRetriggerSync() {
    var presence = DevicePresence()
    XCTAssertTrue(presence.update([100]))
    let generation = presence.generation
    XCTAssertFalse(presence.update([100]))
    XCTAssertEqual(presence.generation, generation)
    XCTAssertTrue(presence.acceptsResult(from: generation))
  }

  func testRemovingOneOfMultipleDevicesIsStillConnected() {
    var presence = DevicePresence()
    presence.update([100, 101])
    let generation = presence.generation
    presence.update([101])
    XCTAssertEqual(presence.isConnected, true)
    XCTAssertFalse(presence.acceptsResult(from: generation))
  }

  func testUnplugDropsPendingAutomaticSyncButReplugQueuesOne() {
    var schedule = SyncSchedule(automaticEnabled: true, intervalMinutes: 30)
    XCTAssertTrue(schedule.request(.automatic))
    XCTAssertFalse(schedule.request(.automatic))
    schedule.cancelAutomaticRequests()
    XCTAssertFalse(schedule.finish(disconnected: true))
    XCTAssertTrue(schedule.request(.automatic))
    // Replug during another transaction queues exactly one fresh sync.
    XCTAssertFalse(schedule.request(.automatic))
    XCTAssertTrue(schedule.finish(disconnected: false))
    XCTAssertFalse(schedule.finish(disconnected: false))
  }

  func testConnectionNotificationDoesNotEnableAutomaticSync() {
    var schedule = SyncSchedule(automaticEnabled: false, intervalMinutes: 30)
    var presence = DevicePresence()
    presence.update([100])
    XCTAssertFalse(schedule.request(.automatic))
    XCTAssertFalse(schedule.isRunning)
    XCTAssertTrue(schedule.request(.manual))
  }
  @MainActor
  func testMonitorInitialSnapshotAndRelease() throws {
    var callbacks = 0
    var monitor: DeviceConnectionMonitor? = try DeviceConnectionMonitor { _ in callbacks += 1 }
    weak var reference = monitor
    // Read registry metadata only. No HID device is opened and no reports sent.
    let matching = try XCTUnwrap(IOServiceMatching("IOHIDDevice"))
    let criteria = matching as NSMutableDictionary
    criteria[kIOHIDVendorIDKey] = CidooConstants.vendorID
    criteria[kIOHIDProductIDKey] = CidooConstants.productID
    criteria[kIOHIDPrimaryUsagePageKey] = CidooConstants.usagePageScreen
    criteria[kIOHIDPrimaryUsageKey] = CidooConstants.usageScreen
    var iterator: io_iterator_t = 0
    XCTAssertEqual(IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator), KERN_SUCCESS)
    defer { IOObjectRelease(iterator) }
    var ids: Set<UInt64> = []
    while true {
      let service = IOIteratorNext(iterator)
      guard service != 0 else { break }
      defer { IOObjectRelease(service) }
      var id: UInt64 = 0
      XCTAssertEqual(IORegistryEntryGetRegistryEntryID(service, &id), KERN_SUCCESS)
      ids.insert(id)
    }
    XCTAssertEqual(monitor?.deviceIDs, ids)
    XCTAssertEqual(callbacks, 0, "Initial enumeration must not trigger duplicate startup syncs")
    monitor = nil
    XCTAssertNil(reference, "Registry notifications must not retain the monitor")
  }

}

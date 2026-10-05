import XCTest
import IOKit
@testable import CidooCore

final class SyncScheduleTests: XCTestCase {
  func testSavedDisabledPreferencePreventsStartupAndWakeSync() {
    var schedule = SyncSchedule(automaticEnabled: false, intervalMinutes: 15)
    XCTAssertEqual(schedule.intervalSeconds, 900)
    XCTAssertFalse(schedule.request(.automatic))
    XCTAssertFalse(schedule.shouldRetry)
    XCTAssertTrue(schedule.request(.manual))
    XCTAssertFalse(schedule.finish(disconnected: true))
    XCTAssertFalse(schedule.shouldRetry)
  }

  func testWakeStormCoalescesWithoutOverlappingTransactions() {
    var schedule = SyncSchedule(automaticEnabled: true, intervalMinutes: 30)
    XCTAssertTrue(schedule.request(.automatic))
    for _ in 0..<100 { XCTAssertFalse(schedule.request(.automatic)) }
    XCTAssertTrue(schedule.finish(disconnected: false))
    XCTAssertTrue(schedule.isRunning)
    XCTAssertFalse(schedule.finish(disconnected: false))
    XCTAssertFalse(schedule.isRunning)
  }

  func testDisablingDuringTransactionDropsQueuedAutomaticWork() {
    var schedule = SyncSchedule(automaticEnabled: true, intervalMinutes: 30)
    XCTAssertTrue(schedule.request(.automatic))
    XCTAssertFalse(schedule.request(.automatic))
    schedule.setAutomaticEnabled(false)
    XCTAssertFalse(schedule.finish(disconnected: true))
    XCTAssertFalse(schedule.shouldRetry)
    XCTAssertFalse(schedule.request(.automatic))
  }

  func testExplicitManualRequestSurvivesDisablingAutomaticSync() {
    var schedule = SyncSchedule(automaticEnabled: true, intervalMinutes: 30)
    XCTAssertTrue(schedule.request(.automatic))
    XCTAssertFalse(schedule.request(.manual))
    schedule.setAutomaticEnabled(false)
    XCTAssertTrue(schedule.finish(disconnected: false))
    XCTAssertFalse(schedule.finish(disconnected: false))
  }

  func testDisconnectRetryClearsOnSuccessOrOtherError() {
    var schedule = SyncSchedule(automaticEnabled: true, intervalMinutes: 5)
    XCTAssertEqual(schedule.intervalSeconds, 300)
    XCTAssertEqual(SyncSchedule.retrySeconds, 60)
    XCTAssertTrue(schedule.request(.automatic))
    XCTAssertFalse(schedule.finish(disconnected: true))
    XCTAssertTrue(schedule.shouldRetry)
    XCTAssertTrue(schedule.request(.automatic))
    XCTAssertFalse(schedule.finish(disconnected: false))
    XCTAssertFalse(schedule.shouldRetry)
  }

  func testReenableRestartsAndInvalidIntervalIsClamped() {
    var schedule = SyncSchedule(automaticEnabled: false, intervalMinutes: 0)
    XCTAssertEqual(schedule.intervalSeconds, 60)
    schedule.setAutomaticEnabled(true)
    XCTAssertTrue(schedule.request(.automatic))
    XCTAssertFalse(schedule.finish(disconnected: true))
    schedule.setAutomaticEnabled(false)
    XCTAssertFalse(schedule.shouldRetry)
  }
  func testSavedUTCIsLoadedBeforeStartup() throws {
    let suite = "KeebClockTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let fresh = SyncPreferences(defaults: defaults)
    XCTAssertTrue(fresh.automaticEnabled)
    XCTAssertFalse(fresh.useUTC)
    XCTAssertEqual(fresh.intervalMinutes, 30)
    defaults.set(true, forKey: "useUTC")
    defaults.set(false, forKey: "autoSyncEnabled")
    defaults.set(60, forKey: "intervalMinutes")
    let saved = SyncPreferences(defaults: defaults)
    XCTAssertTrue(saved.useUTC)
    XCTAssertFalse(saved.automaticEnabled)
    XCTAssertEqual(saved.intervalMinutes, 60)
  }

  func testChangingIntervalKeepsInFlightTransactionAndQueuedWork() {
    var schedule = SyncSchedule(automaticEnabled: true, intervalMinutes: 30)
    XCTAssertTrue(schedule.request(.automatic))
    schedule.setInterval(minutes: 15)
    XCTAssertEqual(schedule.intervalSeconds, 900)
    XCTAssertFalse(schedule.request(.automatic))
    XCTAssertTrue(schedule.finish(disconnected: false))
    XCTAssertFalse(schedule.finish(disconnected: false))
  }

  func testPermissionAndBusyErrorsAreDistinctFromOtherIOFailures() {
    for code in [kIOReturnNotPermitted, kIOReturnNotPrivileged] {
      let error = hidFailure(operation: "Opening", code: code)
      XCTAssertTrue(error.isAccessDenied)
      XCTAssertTrue(error.description.contains("administrator"))
      XCTAssertTrue(error.description.contains("Input Monitoring"))
      XCTAssertTrue(error.description.contains("opening"))
    }
    if case .deviceBusy = hidFailure(operation: "Opening", code: kIOReturnExclusiveAccess) {} else {
      XCTFail("Exclusive access must explain a conflicting app")
    }
    XCTAssertFalse(hidFailure(operation: "Opening", code: kIOReturnNoDevice).isAccessDenied)
  }

}

import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

/// Observes screen-interface connections without opening HID devices.
@MainActor
public final class DeviceConnectionMonitor {
  public private(set) var deviceIDs: Set<UInt64> = []
  private let resources = DeviceNotificationResources()
  private let onChange: @MainActor (Set<UInt64>) -> Void
  private var starting = true

  public init(onChange: @escaping @MainActor (Set<UInt64>) -> Void) throws {
    self.onChange = onChange
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
      throw CidooCoreError.io("Could not create device connection notifications.")
    }
    resources.port = port
    guard let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
      throw CidooCoreError.io("Could not create the device notification run loop.")
    }
    resources.source = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
    let context = Unmanaged.passUnretained(self).toOpaque()
    for attached in [true, false] {
      guard let matching = IOServiceMatching("IOHIDDevice") else {
        throw CidooCoreError.io("Could not match the keyboard screen interface.")
      }
      let criteria = matching as NSMutableDictionary
      criteria[kIOHIDVendorIDKey] = CidooConstants.vendorID
      criteria[kIOHIDProductIDKey] = CidooConstants.productID
      criteria[kIOHIDPrimaryUsagePageKey] = CidooConstants.usagePageScreen
      criteria[kIOHIDPrimaryUsageKey] = CidooConstants.usageScreen
      var iterator: io_iterator_t = 0
      let callback: IOServiceMatchingCallback = attached ? { context, iterator in
        guard let context else { return }
        let monitor = Unmanaged<DeviceConnectionMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.drain(iterator, attached: true) }
      } : { context, iterator in
        guard let context else { return }
        let monitor = Unmanaged<DeviceConnectionMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.drain(iterator, attached: false) }
      }
      let result = IOServiceAddMatchingNotification(port,
        attached ? kIOFirstMatchNotification : kIOTerminatedNotification,
        matching, callback, context, &iterator)
      guard result == KERN_SUCCESS else {
        throw CidooCoreError.io("Could not watch keyboard connections (code \(result)).")
      }
      resources.iterators.append(iterator)
      // Iterators must be drained immediately to arm future notifications.
      drain(iterator, attached: attached)
    }
    starting = false
  }

  private func drain(_ iterator: io_iterator_t, attached: Bool) {
    let previous = deviceIDs
    while true {
      let service = IOIteratorNext(iterator)
      guard service != 0 else { break }
      defer { IOObjectRelease(service) }
      // The initial termination iterator is drained only to arm it. Existing
      // services are seeded exclusively by the initial first-match iterator.
      if starting && !attached { continue }
      var id: UInt64 = 0
      if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS {
        if attached { deviceIDs.insert(id) } else { deviceIDs.remove(id) }
      }
    }
    if !starting && previous != deviceIDs { onChange(deviceIDs) }
  }
}

// Resources are configured only on the main actor. Their destructor can safely
// unregister the run-loop source and release IOKit objects on any thread.
private final class DeviceNotificationResources: @unchecked Sendable {
  var port: IONotificationPortRef?
  var source: CFRunLoopSource?
  var iterators: [io_iterator_t] = []

  deinit {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
    for iterator in iterators { IOObjectRelease(iterator) }
    if let port { IONotificationPortDestroy(port) }
  }
}

/// A generation changes on every real attachment/removal, including rapid
/// unplug/replug. Results from an older generation must not claim verification.
public struct DevicePresence: Sendable {
  public private(set) var deviceIDs: Set<UInt64>?
  public private(set) var generation: UInt64 = 0
  public var isConnected: Bool? { deviceIDs.map { !$0.isEmpty } }
  public init() {}

  @discardableResult
  public mutating func update(_ ids: Set<UInt64>) -> Bool {
    guard deviceIDs != ids else { return false }
    deviceIDs = ids
    generation &+= 1
    return true
  }

  public func acceptsResult(from generation: UInt64) -> Bool {
    self.generation == generation && isConnected != false
  }
}

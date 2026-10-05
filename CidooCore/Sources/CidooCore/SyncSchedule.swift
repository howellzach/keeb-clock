import Foundation

/// Serializes sync requests and coalesces pending triggers.
public struct SyncSchedule: Sendable {
  public enum Trigger: Sendable { case manual, automatic }
  public private(set) var automaticEnabled: Bool
  public private(set) var isRunning = false
  public private(set) var shouldRetry = false
  public private(set) var intervalSeconds: TimeInterval
  public static let retrySeconds: TimeInterval = 60
  private var pendingManual = false
  private var pendingAutomatic = false

  public init(automaticEnabled: Bool, intervalMinutes: Int) {
    self.automaticEnabled = automaticEnabled
    intervalSeconds = TimeInterval(max(1, intervalMinutes)) * 60
  }

  public mutating func setInterval(minutes: Int) {
    intervalSeconds = TimeInterval(max(1, minutes)) * 60
  }

  public mutating func setAutomaticEnabled(_ enabled: Bool) {
    automaticEnabled = enabled
    if !enabled {
      pendingAutomatic = false
      shouldRetry = false
    }
  }

  public mutating func cancelAutomaticRequests() {
    pendingAutomatic = false
    shouldRetry = false
  }

  /// True means the caller owns a new transaction. Repeated triggers coalesce.
  public mutating func request(_ trigger: Trigger) -> Bool {
    if case .automatic = trigger, !automaticEnabled { return false }
    if isRunning {
      switch trigger {
      case .manual: pendingManual = true
      case .automatic: pendingAutomatic = true
      }
      return false
    }
    isRunning = true
    return true
  }

  /// True means one queued transaction should start immediately.
  public mutating func finish(disconnected: Bool) -> Bool {
    precondition(isRunning)
    isRunning = false
    shouldRetry = disconnected && automaticEnabled
    let followUp = pendingManual || (pendingAutomatic && automaticEnabled)
    pendingManual = false
    pendingAutomatic = false
    if followUp { isRunning = true }
    return followUp
  }
}

/// Read all saved preferences before scheduling the first transaction.
public struct SyncPreferences {
  public let intervalMinutes: Int
  public let useUTC: Bool
  public let automaticEnabled: Bool

  public init(intervalMinutes: Int = 30, useUTC: Bool = false, automaticEnabled: Bool = true) {
    self.intervalMinutes = max(1, intervalMinutes)
    self.useUTC = useUTC
    self.automaticEnabled = automaticEnabled
  }

  public init(defaults: UserDefaults) {
    let saved = defaults.integer(forKey: "intervalMinutes")
    intervalMinutes = saved > 0 ? saved : 30
    useUTC = defaults.bool(forKey: "useUTC")
    automaticEnabled = defaults.object(forKey: "autoSyncEnabled") as? Bool ?? true
  }
}

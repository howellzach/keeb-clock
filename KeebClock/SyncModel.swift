import AppKit
import Combine
import Foundation
import CidooCore

@MainActor
final class SyncModel: NSObject, ObservableObject {
  @Published var status: String = "Idle"
  @Published var lastError: String? = nil
  @Published private(set) var monitoringError: String?
  @Published var lastSync: Date? = nil
  @Published private(set) var isSyncing = false

  @Published var intervalMinutes: Int {
    didSet {
      if intervalMinutes < 1 { intervalMinutes = 1; return }
      UserDefaults.standard.set(intervalMinutes, forKey: "intervalMinutes")
      schedule.setInterval(minutes: intervalMinutes)
      start()
    }
  }

  @Published var useUTC: Bool {
    didSet {
      UserDefaults.standard.set(useUTC, forKey: "useUTC")
      syncOnce()
    }
  }

  @Published var autoSyncEnabled: Bool {
    didSet {
      UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled")
      schedule.setAutomaticEnabled(autoSyncEnabled)
      if autoSyncEnabled { start() } else { stop(); status = presence.isConnected == false ? "Disconnected" : (isSyncing ? "Finishing sync…" : "Connected · auto sync off") }
    }
  }

  private var timer: Timer?
  private var reconnectTimer: Timer?
  private var wakeObserver: NSObjectProtocol?
  private var schedule: SyncSchedule
  private var deviceMonitor: DeviceConnectionMonitor?
  private var presence = DevicePresence()

  init(preview: Bool = false) {
    let saved = preview ? SyncPreferences() : SyncPreferences(defaults: .standard)
    intervalMinutes = saved.intervalMinutes
    useUTC = saved.useUTC
    autoSyncEnabled = saved.automaticEnabled
    schedule = SyncSchedule(automaticEnabled: saved.automaticEnabled, intervalMinutes: saved.intervalMinutes)
    super.init()
    if preview {
      status = "Clock verified"
      lastSync = Date(timeIntervalSince1970: 1_780_358_400)
      return
    }
    do {
      let monitor = try DeviceConnectionMonitor { [weak self] ids in
        self?.connectionChanged(ids)
      }
      deviceMonitor = monitor
      connectionChanged(monitor.deviceIDs, syncOnConnect: false)
    } catch {
      monitoringError = "Live connection status is unavailable. Status will update during sync. Details: \(error)"
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.autoSyncEnabled else { return }
        self.syncOnce(trigger: .automatic)
      }
    }
    start()
  }

  func start() {
    stop()
    guard autoSyncEnabled else { status = presence.isConnected == false ? "Disconnected" : "Auto sync off"; return }
    syncOnce(trigger: .automatic)

    let t = Timer(
      timeInterval: schedule.intervalSeconds,
      target: self,
      selector: #selector(timerFired),
      userInfo: nil,
      repeats: true
    )
    timer = t
    RunLoop.main.add(t, forMode: .common)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    reconnectTimer?.invalidate()
    reconnectTimer = nil
  }

  @objc private func timerFired() {
    syncOnce(trigger: .automatic)
  }

  func syncOnce(trigger: SyncSchedule.Trigger = .manual) {
    if case .automatic = trigger, presence.isConnected == false {
      status = "Disconnected"
      return
    }
    guard schedule.request(trigger) else { return }
    performSync()
  }

  private func performSync() {
    isSyncing = true
    status = "Syncing…"
    let utc = useUTC
    let connectionGeneration = presence.generation

    Task { @MainActor in
      let result = await Self.runSync(utc: utc)
      if presence.acceptsResult(from: connectionGeneration) {
        apply(result: result)
      }

      let disconnected: Bool
      if presence.isConnected == false { disconnected = true }
      else if case .failure(CidooCoreError.noDeviceFound) = result { disconnected = true }
      else { disconnected = false }
      let followUp = schedule.finish(disconnected: disconnected)
      updateReconnectTimer()
      isSyncing = false
      if !autoSyncEnabled && !followUp && lastError == nil && presence.isConnected != false { status = "Connected · auto sync off" }
      if followUp { performSync() }
    }
  }

  private func apply(result: Result<Void, Error>) {
    switch result {
    case .success:
      reconnectTimer?.invalidate()
      reconnectTimer = nil
      lastError = nil
      lastSync = Date()
      status = "Clock verified"
    case .failure(let err):
      if let e = err as? CidooCoreError {
        lastError = e.description
      } else {
        lastError = "\(err)"
      }
      if case CidooCoreError.noDeviceFound = err {
        status = "Disconnected"
      } else {
        status = (err as? CidooCoreError)?.isAccessDenied == true ? "Permission needed" : "Sync failed"
        reconnectTimer?.invalidate()
        reconnectTimer = nil
      }
    }
  }

  private func connectionChanged(_ ids: Set<UInt64>, syncOnConnect: Bool = true) {
    guard presence.update(ids) else { return }
    lastError = nil
    reconnectTimer?.invalidate()
    reconnectTimer = nil
    if ids.isEmpty {
      // A result already in flight belongs to the previous generation. It may
      // finish, but cannot turn this state back into “Clock verified”.
      schedule.cancelAutomaticRequests()
      status = "Disconnected"
    } else {
      status = autoSyncEnabled ? "Connected" : "Connected · auto sync off"
      if syncOnConnect && autoSyncEnabled { syncOnce(trigger: .automatic) }
    }
  }

  private func updateReconnectTimer() {
    guard schedule.shouldRetry && deviceMonitor == nil else {
      reconnectTimer?.invalidate()
      reconnectTimer = nil
      return
    }
    guard reconnectTimer == nil else { return }
    let timer = Timer(timeInterval: SyncSchedule.retrySeconds, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.syncOnce(trigger: .automatic) }
    }
    reconnectTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  nonisolated private static func runSync(utc: Bool) async -> Result<Void, Error> {
    await Task.detached(priority: .utility) {
      Result {
        _ = try CidooCore.syncTime(
          dryRun: false,
          utc: utc
        )
      }
    }.value
  }
}

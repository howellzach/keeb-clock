import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemModel: ObservableObject {
  @Published var enabled: Bool = (SMAppService.mainApp.status == .enabled)
  @Published var errorText: String? = nil
  @Published var needsApproval = (SMAppService.mainApp.status == .requiresApproval)

  func refresh() {
    enabled = (SMAppService.mainApp.status == .enabled)
    needsApproval = (SMAppService.mainApp.status == .requiresApproval)
  }

  func setEnabled(_ on: Bool) {
    errorText = nil
    do {
      if on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      errorText = "Couldn’t change Start at login. Keep Keeb Clock in Applications and check General → Login Items in System Settings. Details: \(error.localizedDescription)"
    }
    refresh()
  }
}

@main
struct KeebClockApp: App {
  @StateObject private var model = SyncModel()
  @StateObject private var login = LoginItemModel()

  init() {
    #if SCREENSHOT
    // Preview mode does not access USB.
    if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--screenshot" {
      NSApplication.shared.finishLaunching()
      NSApplication.shared.appearance = NSAppearance(named: .aqua)
      let preview = SyncModel(preview: true)
      let login = LoginItemModel()
      let host = NSHostingView(rootView: ClockMenuView(model: preview, login: login)
        .environment(\.colorScheme, .light))
      host.appearance = NSAppearance(named: .aqua)
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = host
      window.backgroundColor = .windowBackgroundColor
      window.orderFrontRegardless()
      // SwiftUI lays out and renders on the next run-loop turns.
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let capture = Process()
      capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), CommandLine.arguments[2]]
      do {
        try capture.run()
        capture.waitUntilExit()
        exit(capture.terminationStatus)
      } catch {
        FileHandle.standardError.write(Data("Screenshot failed: \(error)\n".utf8))
        exit(1)
      }
    }
    #endif
  }

  var body: some Scene {
    MenuBarExtra {
      ClockMenuView(model: model, login: login)
    } label: {
      Image(nsImage: MenuBarIcon.image)
        .renderingMode(.template)
        .accessibilityLabel("Keeb Clock")
    }
    .menuBarExtraStyle(.window)
  }
}

struct ClockMenuView: View {
  @ObservedObject var model: SyncModel
  @ObservedObject var login: LoginItemModel

  var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Keeb Clock")
          .font(.headline)
        Text("Clock sync for CIDOO ABM066")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(appVersionLabel)
          .font(.caption2)
          .foregroundStyle(.secondary)

        Text("Status: \(model.status)")
          .font(.subheadline)

        if let lastSync = model.lastSync {
          Text("Last sync: \(lastSync.formatted(date: Calendar.current.isDateInToday(lastSync) ? .omitted : .abbreviated, time: .standard))")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Last sync: Never")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let err = model.lastError {
          Divider()
          Text(err)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }

        if let error = model.monitoringError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }

        Divider()

        Toggle("Auto sync", isOn: $model.autoSyncEnabled)
        Toggle("Use UTC", isOn: $model.useUTC)

          Menu("Interval: \(model.intervalMinutes) min") {
              ForEach([5, 15, 30, 60], id: \.self) { m in
                  Button {
                      model.intervalMinutes = m
                  } label: {
                      if model.intervalMinutes == m {
                          Label("\(m) min", systemImage: "checkmark")
                      } else {
                          Text("\(m) min")
                      }
                  }
              }
          }

        Toggle(
          "Start at login",
          isOn: Binding(
            get: { login.enabled },
            set: { login.setEnabled($0) }
          )
        )

        if let err = login.errorText {
          Text(err)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }

        if login.needsApproval || login.errorText != nil {
          Button("Allow in Login Items settings…") {
            SMAppService.openSystemSettingsLoginItems()
          }
        }

        Divider()

        Button("Sync now") { model.syncOnce() }
          .disabled(model.isSyncing)

        Text("Independent project. Not affiliated with\nor endorsed by CIDOO.")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button("Quit Keeb Clock") { NSApplication.shared.terminate(nil) }
      }
      .padding(16)
      .frame(width: 320)
      .onAppear { login.refresh() }
  }
}

private var appVersionLabel: String {
  let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
  let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  return "Version \(version) (build \(build))"
}

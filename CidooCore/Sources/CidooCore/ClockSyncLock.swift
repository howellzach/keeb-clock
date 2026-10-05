import Darwin

// Shares the Go CLI's per-user lock to prevent concurrent HID transactions.
final class ClockSyncLock {
  private var descriptor: Int32

  init() throws {
    let path = "/private/tmp/cidoo-clock-\(getuid()).lock"
    descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CidooCoreError.io("Cannot open clock sync lock: \(errno)") }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFREG else {
      release()
      throw CidooCoreError.io("Unsafe clock sync lock file.")
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      release()
      throw CidooCoreError.io("Another clock sync is already running.")
    }
  }

  func release() {
    guard descriptor >= 0 else { return }
    _ = flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
    descriptor = -1
  }

  deinit { release() }
}

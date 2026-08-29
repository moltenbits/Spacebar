import AppKit
import Darwin
import Foundation

/// Resolves the bundle identifier for a process without relying solely on
/// Launch Services having observed a newly started application.
enum ProcessBundleIdentifierResolver {
  static func resolve(pid: Int) -> String? {
    resolve(
      pid: pid,
      registeredBundleIdentifier: { processID in
        NSRunningApplication(processIdentifier: pid_t(processID))?.bundleIdentifier
      },
      executablePath: executablePath)
  }

  static func resolve(
    pid: Int,
    registeredBundleIdentifier: (Int) -> String?,
    executablePath: (Int) -> String?
  ) -> String? {
    if let bundleID = registeredBundleIdentifier(pid) {
      return bundleID
    }
    guard let path = executablePath(pid),
      let appPath = AppBundlePathResolver.containingAppBundlePath(forExecutablePath: path)
    else {
      return nil
    }
    return Bundle(path: appPath)?.bundleIdentifier
  }

  private static func executablePath(pid: Int) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let length = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(cString: buffer)
  }
}

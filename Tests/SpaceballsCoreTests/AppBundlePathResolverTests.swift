import Foundation
import Testing

@testable import SpaceballsCore

@Suite("AppBundlePathResolver")
struct AppBundlePathResolverTests {
  @Test("detects an executable inside an app bundle")
  func detectsExecutableInsideAppBundle() {
    let path = "/tmp/Spaceballs-CLI.app/Contents/MacOS/spaceballs"

    #expect(
      AppBundlePathResolver.containingAppBundlePath(in: path)
        == "/tmp/Spaceballs-CLI.app")
  }

  @Test("rejects non-bundle executable paths")
  func rejectsNonBundleExecutable() {
    #expect(AppBundlePathResolver.containingAppBundlePath(in: "/usr/local/bin/spaceballs") == nil)
  }

  @Test("rejects paths that mention an app outside Contents/MacOS")
  func rejectsNonExecutableBundlePaths() {
    let path = "/tmp/Spaceballs-CLI.app/Contents/Resources/spaceballs"

    #expect(AppBundlePathResolver.containingAppBundlePath(in: path) == nil)
  }

  @Test("resolves symlinked executables into their app bundle")
  func resolvesSymlinkedExecutable() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("spaceballs-bundle-resolver-\(UUID().uuidString)")
    let executable =
      root
      .appendingPathComponent("Spaceballs-CLI.app/Contents/MacOS/spaceballs")
    let symlink = root.appendingPathComponent("bin/spaceballs")

    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: symlink.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    _ = FileManager.default.createFile(atPath: executable.path, contents: Data())
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: executable)
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(
      AppBundlePathResolver.containingAppBundlePath(forExecutablePath: symlink.path)
        == root.appendingPathComponent("Spaceballs-CLI.app").path)
  }

  @Test("resolves a process bundle before AppKit registers the application")
  func resolvesProcessBundleBeforeAppKitRegistration() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("spaceballs-process-resolver-\(UUID().uuidString)")
    let app = root.appendingPathComponent("ColdLaunch.app")
    let executable = app.appendingPathComponent("Contents/MacOS/cold-launch")
    let infoPlist = app.appendingPathComponent("Contents/Info.plist")

    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundleIdentifier": "com.example.cold-launch",
        "CFBundleExecutable": "cold-launch",
        "CFBundlePackageType": "APPL",
      ],
      format: .xml,
      options: 0)
    try plistData.write(to: infoPlist)
    _ = FileManager.default.createFile(atPath: executable.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root) }

    let bundleID = ProcessBundleIdentifierResolver.resolve(
      pid: 123,
      registeredBundleIdentifier: { _ in nil },
      executablePath: { _ in executable.path })

    #expect(bundleID == "com.example.cold-launch")
  }
}

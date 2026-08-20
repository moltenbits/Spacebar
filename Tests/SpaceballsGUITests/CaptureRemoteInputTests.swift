import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsGUILib

@Suite("AppSettings Capture Remote Input")
struct CaptureRemoteInputSettingTests {

  @Test("captureRemoteInput defaults to false")
  func defaultsToOff() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = AppSettings(defaults: defaults)
    #expect(!settings.captureRemoteInput)
    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test("captureRemoteInput persists and loads back")
  func persistence() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!

    let settings1 = AppSettings(defaults: defaults)
    settings1.captureRemoteInput = true

    let settings2 = AppSettings(defaults: defaults)
    #expect(settings2.captureRemoteInput)

    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test("eventTapLocation is HID by default, session when capturing remote input")
  func tapLocationMapping() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = AppSettings(defaults: defaults)

    #expect(settings.eventTapLocation == .cghidEventTap)
    settings.captureRemoteInput = true
    #expect(settings.eventTapLocation == .cgSessionEventTap)
    settings.captureRemoteInput = false
    #expect(settings.eventTapLocation == .cghidEventTap)

    defaults.removePersistentDomain(forName: suiteName)
  }
}

@Suite("SettingsExport Capture Remote Input")
struct CaptureRemoteInputExportTests {

  private func makeSettings() -> (AppSettings, String) {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (AppSettings(defaults: defaults), suiteName)
  }

  @Test("export and apply round-trips captureRemoteInput")
  func roundTrip() {
    let (source, sourceSuite) = makeSettings()
    source.captureRemoteInput = true

    let export = SettingsExport.from(settings: source)

    let (target, targetSuite) = makeSettings()
    #expect(!target.captureRemoteInput)
    export.apply(to: target)
    #expect(target.captureRemoteInput)

    UserDefaults(suiteName: sourceSuite)?.removePersistentDomain(forName: sourceSuite)
    UserDefaults(suiteName: targetSuite)?.removePersistentDomain(forName: targetSuite)
  }

  @Test("decoding an export without the key defaults to false (backward compat)")
  func missingKeyDefaultsToFalse() throws {
    // Simulate a pre-feature export: encode a real export, strip the new key.
    let (settings, suite) = makeSettings()
    settings.captureRemoteInput = true
    let data = try JSONEncoder().encode(SettingsExport.from(settings: settings))
    var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    dict.removeValue(forKey: "captureRemoteInput")
    let stripped = try JSONSerialization.data(withJSONObject: dict)

    let decoded = try JSONDecoder().decode(SettingsExport.self, from: stripped)
    #expect(!decoded.captureRemoteInput)

    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}

import Foundation
import Testing

@testable import SpaceballsGUILib

@Suite("AppSettings Activate Moved Item")
struct ActivateMovedItemSettingTests {

  @Test("activateMovedItem defaults to true")
  func defaultsToOn() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = AppSettings(defaults: defaults)
    #expect(settings.activateMovedItem)
    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test("activateMovedItem persists and loads back")
  func persistence() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!

    let settings1 = AppSettings(defaults: defaults)
    settings1.activateMovedItem = false

    let settings2 = AppSettings(defaults: defaults)
    #expect(!settings2.activateMovedItem)

    defaults.removePersistentDomain(forName: suiteName)
  }
}

@Suite("SettingsExport Activate Moved Item")
struct ActivateMovedItemExportTests {

  private func makeSettings() -> (AppSettings, String) {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (AppSettings(defaults: defaults), suiteName)
  }

  @Test("export and apply round-trips activateMovedItem")
  func roundTrip() {
    let (source, sourceSuite) = makeSettings()
    source.activateMovedItem = false

    let export = SettingsExport.from(settings: source)

    let (target, targetSuite) = makeSettings()
    #expect(target.activateMovedItem)
    export.apply(to: target)
    #expect(!target.activateMovedItem)

    UserDefaults(suiteName: sourceSuite)?.removePersistentDomain(forName: sourceSuite)
    UserDefaults(suiteName: targetSuite)?.removePersistentDomain(forName: targetSuite)
  }

  @Test("decoding an export without the key defaults to true (backward compat)")
  func missingKeyDefaultsToTrue() throws {
    // Simulate a pre-feature export: encode a real export, strip the new key.
    let (settings, suite) = makeSettings()
    settings.activateMovedItem = false
    let data = try JSONEncoder().encode(SettingsExport.from(settings: settings))
    var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    dict.removeValue(forKey: "activateMovedItem")
    let stripped = try JSONSerialization.data(withJSONObject: dict)

    let decoded = try JSONDecoder().decode(SettingsExport.self, from: stripped)
    #expect(decoded.activateMovedItem)

    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}

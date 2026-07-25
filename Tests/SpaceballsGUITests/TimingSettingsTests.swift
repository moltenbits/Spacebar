import Foundation
import Testing

@testable import SpaceballsCore
@testable import SpaceballsGUILib

@Suite("AppSettings Mission Control Timing")
struct TimingSettingsTests {

  private func makeSettings() -> (AppSettings, String) {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (AppSettings(defaults: defaults), suiteName)
  }

  @Test("Timing defaults match the Core defaults")
  func defaultsMatchCore() {
    let (settings, suite) = makeSettings()
    let core = SpaceMoveTiming()
    #expect(settings.timingSpaceSwitchSettle == core.preSwitchSettle)
    #expect(settings.timingDropSettle == core.dropSettle)
    #expect(settings.timingBetweenDrags == core.interDragPause)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  @Test("Timing values persist and load back")
  func persistence() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!

    let settings1 = AppSettings(defaults: defaults)
    settings1.timingSpaceSwitchSettle = 0.5
    settings1.timingDropSettle = 0.35
    settings1.timingBetweenDrags = 0.0

    let settings2 = AppSettings(defaults: defaults)
    #expect(settings2.timingSpaceSwitchSettle == 0.5)
    #expect(settings2.timingDropSettle == 0.35)
    #expect(settings2.timingBetweenDrags == 0.0)

    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test("moveTiming exposes the settings as a Core timing config")
  func moveTimingBridge() {
    let (settings, suite) = makeSettings()
    settings.timingSpaceSwitchSettle = 1.0
    settings.timingDropSettle = 0.75
    settings.timingBetweenDrags = 0.5
    let timing = settings.moveTiming
    #expect(timing.preSwitchSettle == 1.0)
    #expect(timing.dropSettle == 0.75)
    #expect(timing.interDragPause == 0.5)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  @Test("Export and apply round-trips the timing values")
  func exportRoundTrip() {
    let (source, sourceSuite) = makeSettings()
    source.timingSpaceSwitchSettle = 0.6
    source.timingDropSettle = 0.4
    source.timingBetweenDrags = 0.3

    let export = SettingsExport.from(settings: source)
    let (target, targetSuite) = makeSettings()
    export.apply(to: target)

    #expect(target.timingSpaceSwitchSettle == 0.6)
    #expect(target.timingDropSettle == 0.4)
    #expect(target.timingBetweenDrags == 0.3)

    UserDefaults(suiteName: sourceSuite)?.removePersistentDomain(forName: sourceSuite)
    UserDefaults(suiteName: targetSuite)?.removePersistentDomain(forName: targetSuite)
  }

  @Test("Decoding an export without timing keys falls back to defaults")
  func missingKeysFallBackToDefaults() throws {
    let (source, sourceSuite) = makeSettings()
    let data = try JSONEncoder().encode(SettingsExport.from(settings: source))
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    json.removeValue(forKey: "timingSpaceSwitchSettle")
    json.removeValue(forKey: "timingDropSettle")
    json.removeValue(forKey: "timingBetweenDrags")
    let stripped = try JSONSerialization.data(withJSONObject: json)

    let decoded = try JSONDecoder().decode(SettingsExport.self, from: stripped)
    let core = SpaceMoveTiming()
    #expect(decoded.timingSpaceSwitchSettle == core.preSwitchSettle)
    #expect(decoded.timingDropSettle == core.dropSettle)
    #expect(decoded.timingBetweenDrags == core.interDragPause)

    UserDefaults(suiteName: sourceSuite)?.removePersistentDomain(forName: sourceSuite)
  }
}

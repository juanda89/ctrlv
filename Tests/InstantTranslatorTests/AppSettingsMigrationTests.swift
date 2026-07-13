import ControlVCore
import Foundation
import XCTest
@testable import InstantTranslator

final class AppSettingsMigrationTests: XCTestCase {

    // MARK: - Legacy → profile migration

    func test_decode_legacyFlatShape_synthesizesSingleProfile() throws {
        let legacy = """
        {
          "targetLanguage": "Spanish",
          "tone": "Formal",
          "customTonePrompt": "warm & pro",
          "autoPaste": true,
          "shortcutKeyCode": 9,
          "shortcutModifiers": 768
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)

        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].targetLanguage, .spanish)
        XCTAssertEqual(decoded.profiles[0].tone, .formal)
        XCTAssertEqual(decoded.profiles[0].customTonePrompt, "warm & pro")
        XCTAssertEqual(decoded.profiles[0].shortcutKeyCode, 9)
        XCTAssertTrue(decoded.autoPaste)
    }

    func test_decode_emptyPayload_synthesizesDefaults() throws {
        let empty = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: empty)

        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].targetLanguage, .english)
        XCTAssertEqual(decoded.profiles[0].tone, .original)
        XCTAssertTrue(decoded.autoPaste)
    }

    // MARK: - New format round-trip

    func test_encode_new_thenDecode_preservesProfiles() throws {
        var settings = AppSettings(autoPaste: false)
        settings.profiles = [
            TranslationProfile(targetLanguage: .english, tone: .original, shortcutKeyCode: ShortcutConfiguration.option(forLetter: "V").carbonKeyCode),
            TranslationProfile(targetLanguage: .spanish, tone: .casual, shortcutKeyCode: ShortcutConfiguration.option(forLetter: "J").carbonKeyCode),
        ]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.profiles.count, 2)
        XCTAssertEqual(decoded.profiles[0].targetLanguage, .english)
        XCTAssertEqual(decoded.profiles[1].targetLanguage, .spanish)
        XCTAssertEqual(decoded.profiles[1].tone, .casual)
        XCTAssertFalse(decoded.autoPaste)
    }

    // MARK: - Legacy mirror (downgrade safety)

    func test_encode_writesLegacyFieldsForDowngradeSafety() throws {
        var settings = AppSettings()
        settings.profiles = [
            TranslationProfile(targetLanguage: .portuguese, tone: .concise, customTonePrompt: "brief", shortcutKeyCode: ShortcutConfiguration.option(forLetter: "K").carbonKeyCode)
        ]

        let data = try JSONEncoder().encode(settings)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["targetLanguage"] as? String, "Portuguese")
        XCTAssertEqual(dict?["tone"] as? String, "Concise")
        XCTAssertEqual(dict?["customTonePrompt"] as? String, "brief")
        XCTAssertNotNil(dict?["shortcutKeyCode"])
        XCTAssertNotNil(dict?["profiles"])
    }

    // MARK: - Passthrough accessors

    func test_primaryProfileAccessors_readAndWriteProfileZero() {
        var settings = AppSettings()
        settings.targetLanguage = .french
        settings.tone = .formal

        XCTAssertEqual(settings.profiles[0].targetLanguage, .french)
        XCTAssertEqual(settings.profiles[0].tone, .formal)
        XCTAssertEqual(settings.targetLanguage, .french)
        XCTAssertEqual(settings.tone, .formal)
    }

    // MARK: - Profile CRUD via ViewModel

    @MainActor
    func test_addProfile_stopsAtMaxCap() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { cleanup(defaults, suite: suite) }

        UserDefaults.standard.removeObject(forKey: "appSettings")
        let vm = SettingsViewModel(persistToDisk: false)

        // Starts with 1 default profile
        XCTAssertEqual(vm.settings.profiles.count, 1)

        _ = vm.addProfile()
        _ = vm.addProfile()
        XCTAssertEqual(vm.settings.profiles.count, TranslationProfile.maxProfiles)
        XCTAssertFalse(vm.canAddProfile)

        let extra = vm.addProfile()
        XCTAssertNil(extra)
        XCTAssertEqual(vm.settings.profiles.count, TranslationProfile.maxProfiles)
    }

    @MainActor
    func test_addProfile_assignsUniqueShortcutLetters() {
        let vm = SettingsViewModel(persistToDisk: false)

        _ = vm.addProfile()
        _ = vm.addProfile()

        let codes = vm.settings.profiles.map { $0.shortcutKeyCode }
        XCTAssertEqual(Set(codes).count, codes.count, "Every profile should have a unique shortcut key code")
    }

    @MainActor
    func test_setShortcut_rejectsCollisionWithOtherProfile() {
        let vm = SettingsViewModel(persistToDisk: false)
        _ = vm.addProfile()

        let firstID = vm.settings.profiles[0].id
        let secondID = vm.settings.profiles[1].id
        let firstCode = vm.settings.profiles[0].shortcutKeyCode

        // Try to set profile 2's shortcut to profile 1's letter → should be no-op.
        let attemptedOption = ShortcutConfiguration.option(for: firstCode)
        vm.setShortcut(attemptedOption, forProfile: secondID)

        // Profile 2 keeps whatever letter it had; profile 1 unchanged.
        XCTAssertEqual(vm.settings.profiles[0].shortcutKeyCode, firstCode)
        XCTAssertNotEqual(vm.settings.profiles[1].shortcutKeyCode, firstCode)
        XCTAssertNotEqual(vm.settings.profiles[0].id, vm.settings.profiles[1].id)
        _ = firstID  // silence unused
    }

    @MainActor
    func test_removeProfile_neverRemovesPrimary() {
        let vm = SettingsViewModel(persistToDisk: false)
        let primaryID = vm.settings.profiles[0].id

        vm.removeProfile(id: primaryID)
        XCTAssertEqual(vm.settings.profiles.count, 1, "Primary profile must not be removable")
        XCTAssertEqual(vm.settings.profiles[0].id, primaryID)
    }

    @MainActor
    func test_isShortcutLetterAvailable_reportsCollisions() {
        let vm = SettingsViewModel(persistToDisk: false)
        _ = vm.addProfile()

        let usedByFirst = vm.settings.profiles[0].shortcutKeyCode
        let secondID = vm.settings.profiles[1].id

        XCTAssertFalse(vm.isShortcutLetterAvailable(usedByFirst, excludingProfile: secondID))
        // Any unused letter should be available.
        let unused = ShortcutConfiguration.letterOptions.first(where: { opt in
            !vm.settings.profiles.contains(where: { $0.shortcutKeyCode == opt.carbonKeyCode })
        })!
        XCTAssertTrue(vm.isShortcutLetterAvailable(unused.carbonKeyCode, excludingProfile: secondID))
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suite = "tests.appsettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    private func cleanup(_ defaults: UserDefaults, suite: String) {
        defaults.removePersistentDomain(forName: suite)
    }
}

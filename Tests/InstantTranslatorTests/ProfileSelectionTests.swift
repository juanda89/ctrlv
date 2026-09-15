import ControlVCore
import XCTest
@testable import InstantTranslator

/// The popover tabs edit exactly one profile at a time. These tests pin the
/// selection semantics and that edits never leak across profiles.
final class ProfileSelectionTests: XCTestCase {
    private func makeVM() -> SettingsViewModel { SettingsViewModel(persistToDisk: false) }

    func test_selection_defaultsToPrimary() {
        let vm = makeVM()
        XCTAssertEqual(vm.selectedProfileID, vm.primaryProfileID)
        XCTAssertEqual(vm.selectedProfileIndex, 0)
    }

    func test_addProfileAndSelect_selectsTheNewProfile_withUniqueShortcut() {
        let vm = makeVM()
        let primaryCode = vm.settings.profiles[0].shortcutKeyCode

        let id = vm.addProfileAndSelect()

        XCTAssertNotNil(id)
        XCTAssertEqual(vm.selectedProfileID, id)
        XCTAssertEqual(vm.selectedProfileIndex, 1)
        XCTAssertNotEqual(vm.selectedProfile.shortcutKeyCode, primaryCode)
    }

    func test_editingSelectedProfile_doesNotTouchOthers() {
        let vm = makeVM()
        vm.selectedTargetLanguage = .english
        vm.selectedTone = .original
        vm.selectedCustomTonePrompt = ""
        vm.addProfileAndSelect()

        vm.selectedTargetLanguage = .spanish
        vm.selectedTone = .custom
        vm.selectedCustomTonePrompt = "pirate voice"

        XCTAssertEqual(vm.settings.profiles[0].targetLanguage, .english)
        XCTAssertEqual(vm.settings.profiles[0].tone, .original)
        XCTAssertEqual(vm.settings.profiles[0].customTonePrompt, "")
        XCTAssertEqual(vm.settings.profiles[1].targetLanguage, .spanish)
        XCTAssertEqual(vm.settings.profiles[1].tone, .custom)
        XCTAssertEqual(vm.settings.profiles[1].customTonePrompt, "pirate voice")
    }

    func test_switchingBackToPrimary_editsPrimaryOnly() {
        let vm = makeVM()
        vm.addProfileAndSelect()
        vm.selectedTargetLanguage = .french

        vm.selectProfile(vm.primaryProfileID)
        vm.selectedTargetLanguage = .german

        XCTAssertEqual(vm.settings.profiles[0].targetLanguage, .german)
        XCTAssertEqual(vm.settings.profiles[1].targetLanguage, .french)
    }

    func test_shortcutKeyCaps_followSelectedProfile() {
        let vm = makeVM()
        let primaryLetter = vm.settings.profiles[0].shortcutLetter
        vm.addProfileAndSelect()
        let secondLetter = vm.settings.profiles[1].shortcutLetter

        XCTAssertEqual(vm.shortcutKeyCaps.last, secondLetter)
        vm.selectProfile(vm.primaryProfileID)
        XCTAssertEqual(vm.shortcutKeyCaps.last, primaryLetter)
        XCTAssertNotEqual(primaryLetter, secondLetter)
    }

    func test_removeSelectedProfile_fallsBackToPrimary() {
        let vm = makeVM()
        guard let second = vm.addProfileAndSelect() else { return XCTFail("add failed") }

        vm.removeProfile(id: second)

        XCTAssertEqual(vm.settings.profiles.count, 1)
        XCTAssertEqual(vm.selectedProfileID, vm.primaryProfileID)
    }

    func test_removePrimary_isRejected() {
        let vm = makeVM()
        vm.addProfileAndSelect()

        vm.removeProfile(id: vm.primaryProfileID)

        XCTAssertEqual(vm.settings.profiles.count, 2)
    }

    func test_selectUnknownProfile_isIgnored() {
        let vm = makeVM()
        vm.selectProfile(UUID())
        XCTAssertEqual(vm.selectedProfileID, vm.primaryProfileID)
    }

    func test_shortcutCollision_acrossProfiles_isRejected() {
        let vm = makeVM()
        let primaryOption = ShortcutConfiguration.option(for: vm.settings.profiles[0].shortcutKeyCode)
        guard let second = vm.addProfileAndSelect() else { return XCTFail("add failed") }
        let secondCodeBefore = vm.settings.profiles[1].shortcutKeyCode

        XCTAssertFalse(vm.isShortcutLetterAvailable(primaryOption.carbonKeyCode, excludingProfile: second))
        vm.setShortcut(primaryOption, forProfile: second)

        XCTAssertEqual(vm.settings.profiles[1].shortcutKeyCode, secondCodeBefore, "Collision must be a no-op")
        XCTAssertNotEqual(vm.settings.profiles[0].shortcutKeyCode, vm.settings.profiles[1].shortcutKeyCode)
    }

    func test_addProfile_stopsAtCap_andSelectionStaysValid() {
        let vm = makeVM()
        vm.addProfileAndSelect()
        vm.addProfileAndSelect()
        XCTAssertFalse(vm.canAddProfile)
        XCTAssertNil(vm.addProfileAndSelect())
        XCTAssertEqual(vm.selectedProfileIndex, 2)
        let codes = vm.settings.profiles.map { $0.shortcutKeyCode }
        XCTAssertEqual(Set(codes).count, 3, "All three shortcuts must differ")
    }
}

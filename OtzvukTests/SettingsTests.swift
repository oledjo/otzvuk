import XCTest
@testable import Otzvuk

@MainActor
final class SettingsTests: XCTestCase {
    func testOldSettingsWithoutReverseKeyStillLoad() throws {
        let defaults = UserDefaults(suiteName: "otzvuk-tests-\(UUID().uuidString)")!
        let old = #"{"gapSeconds":3,"timerSeconds":600,"voiceVolume":0.8,"musicVolume":0.2}"#
        defaults.set(Data(old.utf8), forKey: "otzvuk.sessionSettings")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.value.gapSeconds, 3)
        XCTAssertEqual(store.value.timerSeconds, 600)
        XCTAssertFalse(store.value.reversed)
    }

    func testReversedFlagPersists() {
        let defaults = UserDefaults(suiteName: "otzvuk-tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.value.reversed = true
        XCTAssertTrue(SettingsStore(defaults: defaults).value.reversed)
    }

    func testOldLibraryJSONWithPerItemFlagStillLoads() throws {
        let store = TestSupport.tempStore()
        let id = UUID(), name = "\(id.uuidString).m4a"
        try TestSupport.writeTone(to: store.recordingURL(name), seconds: 1)
        let json = #"[{"id":"\#(id.uuidString)","title":"Старая","fileName":"\#(name)","duration":1,"createdAt":0,"playsReversed":true,"isSelected":true}]"#
        try Data(json.utf8).write(to: store.libraryFile)
        let library = Library(store: store)
        XCTAssertEqual(library.affirmations.map(\.title), ["Старая"])
    }
}

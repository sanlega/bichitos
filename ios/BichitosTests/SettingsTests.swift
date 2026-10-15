import XCTest
@testable import Bichitos

@MainActor
final class SettingsTests: XCTestCase {
    private var suite: UserDefaults!
    private let name = "SettingsTests"

    override func setUp() async throws {
        UserDefaults().removePersistentDomain(forName: name)
        suite = UserDefaults(suiteName: name)
        Settings.store = suite
    }

    override func tearDown() async throws {
        Settings.store = .standard
        suite.removePersistentDomain(forName: name)
    }

    func testVoiceAndHapticsStartOnAndAreKeptSeparately() {
        XCTAssertTrue(Settings.voice)
        XCTAssertTrue(Settings.haptics)
        Settings.voice = false
        XCTAssertFalse(Settings.voice)
        XCTAssertTrue(Settings.haptics)
        Settings.haptics = false
        Settings.voice = true
        XCTAssertFalse(Settings.haptics)
        // Same keys the sheet's @AppStorage writes, read back from a fresh handle on the same store.
        XCTAssertEqual(UserDefaults(suiteName: name)?.object(forKey: Settings.hapticsKey) as? Bool, false)
        XCTAssertEqual(UserDefaults(suiteName: name)?.object(forKey: Settings.voiceKey) as? Bool, true)
    }

    func testHapticsRespectTheToggle() {
        let play = Haptics.play
        defer { Haptics.play = play }
        var fired: [Haptics.Kind] = []
        Haptics.play = { fired.append($0) }

        Haptics.fire(.pet)
        Haptics.tap()
        XCTAssertEqual(fired, [.pet, .tap])

        Settings.haptics = false
        Haptics.fire(.success)
        Haptics.tap()
        XCTAssertEqual(fired, [.pet, .tap])
    }
}

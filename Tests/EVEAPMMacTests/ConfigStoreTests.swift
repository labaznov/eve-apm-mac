import XCTest
@testable import EVEAPMMac

@MainActor
final class ConfigStoreTests: XCTestCase {
    private func temporaryLayout() throws -> ProfileLayout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eveapm-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return ProfileLayout(root: root)
    }

    func testAFreshInstallStartsOnTheDefaultProfile() throws {
        XCTAssertEqual(ConfigStore(layout: try temporaryLayout()).currentProfile, "default")
    }

    func testCreatingAProfileSwitchesToIt() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.createProfile(named: "mining")
        XCTAssertEqual(store.currentProfile, "mining")
    }

    func testANewProfileInheritsTheCurrentSettings() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.settings.thumbnailWidth = 321
        store.createProfile(named: "mining")
        XCTAssertEqual(store.settings.thumbnailWidth, 321)
    }

    func testANewProfileCanStartFromDefaults() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.settings.thumbnailWidth = 321
        store.createProfile(named: "mining", copyingCurrent: false)
        XCTAssertEqual(store.settings.thumbnailWidth, Settings().thumbnailWidth)
    }

    func testEachProfileKeepsItsOwnSettings() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.createProfile(named: "mining")
        store.settings.thumbnailWidth = 480
        store.switchTo("default")
        XCTAssertEqual(store.settings.thumbnailWidth, Settings().thumbnailWidth)
    }

    func testSwitchingBackRestoresTheProfileSettings() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.createProfile(named: "mining")
        store.settings.thumbnailWidth = 480
        store.switchTo("default")
        store.switchTo("mining")
        XCTAssertEqual(store.settings.thumbnailWidth, 480)
    }

    func testCyclingReachesTheNextProfile() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.createProfile(named: "mining")
        store.cycleProfile(forward: true)
        XCTAssertEqual(store.currentProfile, "default")
    }

    func testTheLastProfileCannotBeDeleted() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.deleteProfile("default")
        XCTAssertEqual(store.profiles, ["default"])
    }

    func testDeletingTheCurrentProfileFallsBackToAnother() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.createProfile(named: "mining")
        store.deleteProfile("mining")
        XCTAssertEqual(store.currentProfile, "default")
    }

    func testAProfileNameCannotEscapeItsDirectory() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        store.createProfile(named: "../escape")
        XCTAssertEqual(store.currentProfile, "escape")
    }

    func testTheChosenProfileSurvivesARestart() throws {
        let layout = try temporaryLayout()
        let first = ConfigStore(layout: layout)
        first.createProfile(named: "mining")
        first.flush()
        XCTAssertEqual(ConfigStore(layout: layout).currentProfile, "mining")
    }

    func testProfileShortcutsSurviveARestart() throws {
        let layout = try temporaryLayout()
        let first = ConfigStore(layout: layout)
        first.globalHotkeys = [Hotkey(keyCode: 20, modifiers: 4096, action: .cycleProfileForward)]
        XCTAssertEqual(ConfigStore(layout: layout).globalHotkeys, first.globalHotkeys)
    }

    func testAPortableFolderUsesTheFileBesideTheApp() throws {
        let layout = ProfileLayout(root: try temporaryLayout().root, isPortable: true)
        XCTAssertEqual(layout.profileURL("default").lastPathComponent, "settings.json")
    }

    func testAPortableFolderKeepsOtherProfilesTogether() throws {
        let layout = ProfileLayout(root: try temporaryLayout().root, isPortable: true)
        XCTAssertEqual(layout.profileURL("mining").deletingLastPathComponent().lastPathComponent,
                       "profiles")
    }

    func testAPortableFolderAlwaysOffersTheDefaultProfile() throws {
        let layout = ProfileLayout(root: try temporaryLayout().root, isPortable: true)
        XCTAssertEqual(layout.names(), ["default"])
    }

    func testAPortableFileIsLeftWhereTheUserPutIt() throws {
        let root = try temporaryLayout().root
        let layout = ProfileLayout(root: root, isPortable: true)
        try SettingsFile.save(Settings(), to: layout.legacySettingsURL)
        layout.migrateLegacySettings()
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.legacySettingsURL.path))
    }

    func testAPortableFileIsReadAsTheProfile() throws {
        let root = try temporaryLayout().root
        let layout = ProfileLayout(root: root, isPortable: true)
        var portable = Settings()
        portable.thumbnailWidth = 199
        try SettingsFile.save(portable, to: layout.legacySettingsURL)
        XCTAssertEqual(ConfigStore(layout: layout).settings.thumbnailWidth, 199)
    }

    func testAnImportedProfileBecomesItsOwnProfile() throws {
        let store = ConfigStore(layout: try temporaryLayout())
        var imported = Settings()
        imported.thumbnailWidth = 404
        store.adopt(imported, asProfile: "from-windows")
        XCTAssertEqual(store.currentProfile, "from-windows")
    }

    func testSettingsFromBeforeProfilesAreAdopted() throws {
        let layout = try temporaryLayout()
        var legacy = Settings()
        legacy.thumbnailWidth = 271
        try SettingsFile.save(legacy, to: layout.legacySettingsURL)
        XCTAssertEqual(ConfigStore(layout: layout).settings.thumbnailWidth, 271)
    }
}

import Foundation
import Testing
@testable import AlarmDomain

/// Pro sound pack (D-074) matches shared/cosmetics/cosmetics.json; unknown ids still fall back to the default.
struct AlarmSoundTests {
    private struct Catalog: Decodable {
        struct Sound: Decodable { let id: String; let pro: Bool }
        let alarmSounds: [Sound]
    }

    @Test func soundsMatchTheSharedCatalog() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: RepoFile.url("shared/cosmetics/cosmetics.json")))
        #expect(catalog.alarmSounds.map(\.id) == AlarmSounds.bundled)
        #expect(Set(catalog.alarmSounds.filter(\.pro).map(\.id)) == AlarmSounds.pro)
    }

    @Test func everySoundHasAFile() {
        for id in AlarmSounds.bundled {
            let file = RepoFile.url("ios/Pushly/Resources/Sounds/\(AlarmSounds.resourceName(id)).wav")
            #expect(FileManager.default.fileExists(atPath: file.path), "\(id)")
        }
        #expect(AlarmSounds.resourceName("bundled.unknown") == "pulse")
        #expect(AlarmSounds.resourceName("bundled.thunder") == "thunder")
    }
}

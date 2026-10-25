import Foundation
import Testing
@testable import DesignSystem

/// The cosmetics catalog (D-074) matches shared/cosmetics/cosmetics.json — the server checks the same lists.
struct CosmeticsTests {
    private struct Catalog: Decodable {
        struct Frame: Decodable { let id: String; let pro: Bool }
        struct Emblem: Decodable { let id: String; let glyph: String; let pro: Bool }
        struct Badge: Decodable { let shapes: [String]; let colors: [String]; let emblems: [Emblem] }
        let frames: [Frame]
        let clanBadge: Badge
    }

    private static func catalog(file: StaticString = #filePath) throws -> Catalog {
        // .../ios/Packages/DesignSystem/Tests/DesignSystemTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("shared/cosmetics/cosmetics.json"))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test func catalogMatchesTheSharedFile() throws {
        let c = try Self.catalog()
        #expect(c.frames.map(\.id) == Cosmetics.frames)
        #expect(c.frames.allSatisfy(\.pro))
        #expect(c.clanBadge.shapes == Cosmetics.badgeShapes)
        #expect(c.clanBadge.colors == Cosmetics.badgeColors)
        #expect(c.clanBadge.emblems.map(\.id) == Cosmetics.emblems.map(\.id))
        #expect(c.clanBadge.emblems.map(\.glyph) == Cosmetics.emblems.map(\.glyph))
        #expect(c.clanBadge.emblems.map(\.pro) == Cosmetics.emblems.map(\.pro))
    }

    @Test func everyFrameHasColours() {
        for f in Cosmetics.frames { #expect(Cosmetics.frameColors(f) != nil, "\(f)") }
        #expect(Cosmetics.frameColors(nil) == nil)
        #expect(Cosmetics.frameColors("sparkles") == nil)
    }
}

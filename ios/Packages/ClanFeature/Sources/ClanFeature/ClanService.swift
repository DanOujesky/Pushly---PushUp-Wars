import Foundation

/// Backend calls for the clan screens (JSON of shared/contracts), wired in the app from Networking.
public struct ClanService: Sendable {
    public var home: @Sendable () async throws -> Data
    public var clan: @Sendable (_ id: String) async throws -> Data
    public var search: @Sendable (_ query: String) async throws -> Data
    public var create: @Sendable (_ name: String, _ tag: String, _ description: String, _ policy: String) async throws -> Data
    public var join: @Sendable (_ clanId: String, _ message: String?) async throws -> String
    public var respond: @Sendable (_ userId: String, _ accept: Bool) async throws -> String
    public var leave: @Sendable () async throws -> String
    public var kick: @Sendable (_ userId: String) async throws -> Void
    public var setRole: @Sendable (_ userId: String, _ role: String) async throws -> Void
    public var transfer: @Sendable (_ userId: String) async throws -> Void
    public var messages: @Sendable (_ beforeId: Int?) async throws -> Data
    public var send: @Sendable (_ body: String, _ kind: String) async throws -> Void
    /// Finished wars of my clan (clan-war-history.schema.json).
    public var warHistory: @Sendable () async throws -> Data
    /// War Chests + medals (war-chests.schema.json).
    public var chests: @Sendable () async throws -> Data
    public var openChest: @Sendable (_ id: String) async throws -> Data
    /// `clan_rally()` (D-068): push + chat to the whole clan; returns the war card.
    public var rally: @Sendable () async throws -> Data

    public init(
        home: @escaping @Sendable () async throws -> Data,
        clan: @escaping @Sendable (String) async throws -> Data,
        search: @escaping @Sendable (String) async throws -> Data,
        create: @escaping @Sendable (String, String, String, String) async throws -> Data,
        join: @escaping @Sendable (String, String?) async throws -> String,
        respond: @escaping @Sendable (String, Bool) async throws -> String,
        leave: @escaping @Sendable () async throws -> String,
        kick: @escaping @Sendable (String) async throws -> Void,
        setRole: @escaping @Sendable (String, String) async throws -> Void,
        transfer: @escaping @Sendable (String) async throws -> Void,
        messages: @escaping @Sendable (Int?) async throws -> Data,
        send: @escaping @Sendable (String, String) async throws -> Void,
        warHistory: @escaping @Sendable () async throws -> Data = { Data("[]".utf8) },
        chests: @escaping @Sendable () async throws -> Data = { Data(#"{"unopened":[],"medals":{"gold":0,"silver":0,"bronze":0}}"#.utf8) },
        openChest: @escaping @Sendable (String) async throws -> Data = { _ in Data("{}".utf8) },
        rally: @escaping @Sendable () async throws -> Data = { throw CancellationError() }
    ) {
        self.rally = rally
        self.warHistory = warHistory
        self.chests = chests
        self.openChest = openChest
        self.home = home
        self.clan = clan
        self.search = search
        self.create = create
        self.join = join
        self.respond = respond
        self.leave = leave
        self.kick = kick
        self.setRole = setRole
        self.transfer = transfer
        self.messages = messages
        self.send = send
    }
}

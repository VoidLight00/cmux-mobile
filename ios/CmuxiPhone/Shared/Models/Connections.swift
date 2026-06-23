import Foundation

/// One saved Mac bridge: name + address + its pairing token.
/// Holding the token lets us switch Macs with a tap — no re-pairing.
///
/// The `token` is a secret and is NEVER encoded into UserDefaults — `CodingKeys`
/// omits it, so the persisted list carries only non-secret metadata. The token
/// lives in the Keychain (see `ConnectionStore`), keyed by this connection's id.
struct SavedConnection: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int
    var token: String = ""

    enum CodingKeys: String, CodingKey { case id, name, host, port }
}

/// Persists the list of paired Macs and which one is active.
/// Backs the "Macs" switcher in Settings.
final class ConnectionStore: ObservableObject {

    static let shared = ConnectionStore()

    @Published private(set) var connections: [SavedConnection] = []
    @Published private(set) var activeID: UUID?

    private let listKey = "saved_connections_v1"
    private let activeKey = "active_connection_id"

    /// Keychain account for a connection's bearer token.
    private static func tokenAccount(_ id: UUID) -> String { "conn_\(id.uuidString)" }

    /// Legacy shape: older builds JSON-encoded the token into UserDefaults. Used
    /// only to recover + migrate those tokens into the Keychain on first load.
    private struct LegacyConnection: Decodable {
        var id: UUID
        var token: String?
    }

    private init() {
        load()
    }

    var active: SavedConnection? {
        connections.first { $0.id == activeID }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: listKey),
           let list = try? JSONDecoder().decode([SavedConnection].self, from: data) {
            // Recover any tokens still embedded in a legacy UserDefaults blob.
            let legacy = (try? JSONDecoder().decode([LegacyConnection].self, from: data)) ?? []
            let legacyTokens = Dictionary(legacy.compactMap { l -> (UUID, String)? in
                guard let t = l.token, !t.isEmpty else { return nil }
                return (l.id, t)
            }, uniquingKeysWith: { a, _ in a })

            var migrated = false
            connections = list.map { conn in
                var c = conn
                if let kc = KeychainStore.get(Self.tokenAccount(conn.id)) {
                    c.token = kc
                } else if let legacyToken = legacyTokens[conn.id] {
                    c.token = legacyToken
                    KeychainStore.set(legacyToken, for: Self.tokenAccount(conn.id)) // migrate
                    migrated = true
                }
                return c
            }
            // Re-persist in the token-less format to scrub plaintext tokens from UserDefaults.
            if migrated { persist() }
        }
        if let s = UserDefaults.standard.string(forKey: activeKey) {
            activeID = UUID(uuidString: s)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(connections) { // token omitted via CodingKeys
            UserDefaults.standard.set(data, forKey: listKey)
        }
        for c in connections {
            KeychainStore.set(c.token, for: Self.tokenAccount(c.id))
        }
        UserDefaults.standard.set(activeID?.uuidString, forKey: activeKey)
    }

    /// Insert or update a connection (matched by host:port) and make it active.
    @discardableResult
    func upsert(name: String, host: String, port: Int, token: String) -> SavedConnection {
        if let idx = connections.firstIndex(where: { $0.host == host && $0.port == port }) {
            connections[idx].name = name
            connections[idx].token = token
            activeID = connections[idx].id
            persist()
            return connections[idx]
        }
        let conn = SavedConnection(name: name, host: host, port: port, token: token)
        connections.append(conn)
        activeID = conn.id
        persist()
        return conn
    }

    func setActive(_ id: UUID) {
        activeID = id
        persist()
    }

    /// Rename a saved connection (e.g. to "office-1").
    func rename(_ id: UUID, to name: String) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].name = name
        persist()
    }

    func remove(_ id: UUID) {
        connections.removeAll { $0.id == id }
        KeychainStore.delete(Self.tokenAccount(id))
        if activeID == id {
            activeID = connections.first?.id
        }
        persist()
    }
}

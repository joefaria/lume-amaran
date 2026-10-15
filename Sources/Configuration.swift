import Foundation
import Security
import SQLite3
import CryptoKit

struct LightConfiguration: Codable, Identifiable {
    var name: String
    var netKey: String
    var appKey: String
    var address: UInt16
    var source: UInt16 = 0
    var deviceKey: String?
    var needsConfiguration: Bool?
    var peripheralUUID: String?
    var id: String { "\(Bytes(SHA256.hash(data: Data(netKey.utf8))).prefix(8).map { String(format: "%02x", $0) }.joined())-\(address)" }
    func validated() throws -> LightConfiguration {
        guard try Bytes(hex: netKey).count == 16, try Bytes(hex: appKey).count == 16,
              (2...0x6fff).contains(address), name.count <= 150 else { throw LumeError.message("Configuração da luz inválida.") }
        return self
    }
    var mesh: Mesh { get throws { try Mesh(net: Bytes(hex: netKey), app: Bytes(hex: appKey)) } }
}

enum ConfigurationImport {
    static func json(_ data: Data) throws -> [LightConfiguration] {
        guard data.count < 5_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LumeError.message("Este arquivo não contém uma configuração compatível.")
        }
        if root["netKeys"] != nil { return try sidus(root) }
        let rows = (root["lights"] ?? root["fixtures"]) as? [[String: Any]] ?? [root]
        return try rows.map { row in
            let net = (row["net_key"] ?? row["netKey"] ?? root["net_key"] ?? root["netKey"]) as? String ?? ""
            let app = (row["app_key"] ?? row["appKey"] ?? root["app_key"] ?? root["appKey"]) as? String ?? ""
            let value = row["node_address"] ?? row["address"]
            let addr = (value as? NSNumber)?.intValue ?? Int(value as? String ?? "") ?? -1
            guard let address = UInt16(exactly: addr) else { throw LumeError.message("Endereço da luz inválido.") }
            return try LightConfiguration(name: row["name"] as? String ?? "amaran 60x S", netKey: net, appKey: app, address: address).validated()
        }
    }
    private static func sidus(_ root: [String: Any]) throws -> [LightConfiguration] {
        guard let networks = root["netKeys"] as? [[String: Any]], let apps = root["appKeys"] as? [[String: Any]],
              let nodes = root["nodes"] as? [[String: Any]], networks.count == 1, apps.count == 1,
              let net = networks[0]["key"] as? String, let app = apps[0]["key"] as? String else {
            throw LumeError.message("O arquivo do Sidus Link precisa conter uma única rede de iluminação.")
        }
        return try nodes.compactMap { node in
            let address: UInt16?
            if let text = node["unicastAddress"] as? String { address = UInt16(text.replacingOccurrences(of: "0x", with: ""), radix: 16) }
            else if let n = node["unicastAddress"] as? NSNumber { address = UInt16(exactly: n.intValue) }
            else { address = nil }
            guard let address, address > 1 else { return nil }
            let name = node["name"] as? String ?? "amaran 60x S"
            return try LightConfiguration(name: name, netKey: net, appKey: app, address: address).validated()
        }
    }
    static func iphoneBackup(_ folder: URL) throws -> [LightConfiguration] {
        let plist = folder.appendingPathComponent("Manifest.plist")
        if let data = try? Data(contentsOf: plist),
           let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           dictionary["IsEncrypted"] as? Bool == true {
            throw LumeError.message("Este backup é criptografado. Nesta versão, selecione uma exportação JSON do Sidus Link ou um backup local não criptografado já existente. Não altere a proteção do seu backup.")
        }
        var db: OpaquePointer?
        let path = folder.appendingPathComponent("Manifest.db").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            throw LumeError.message("Selecione a pasta do backup que contém Manifest.db.")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT fileID FROM Files WHERE flags=1 AND domain IN ('AppDomain-com.aputure.cn.SidusLink','AppDomain-com.siduslink.cn.Acrux.hd') AND relativePath LIKE 'Documents/mesh/%.json' LIMIT 100"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw LumeError.message("Não foi possível ler o backup do iPhone.") }
        defer { sqlite3_finalize(statement) }
        var lights: [LightConfiguration] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let id = String(cString: raw)
            guard id.count == 40, id.allSatisfy({ $0.isHexDigit }) else { continue }
            let file = folder.appendingPathComponent(String(id.prefix(2))).appendingPathComponent(id)
            let values = try json(Data(contentsOf: file)); lights += values
        }
        guard !lights.isEmpty else { throw LumeError.message("Não encontrei a configuração do Sidus Link neste backup. A versão do aplicativo pode usar outro formato.") }
        var seen: Set<String> = []
        return lights.filter { seen.insert($0.id).inserted }
    }
    static func database(_ path: String) throws -> [LightConfiguration] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }; throw LumeError.message("Não foi possível ler a configuração do amaran Desktop.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)
        func query(_ sql: String) throws -> [[String: String]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw LumeError.message("Formato de configuração ainda não suportado.") }
            defer { sqlite3_finalize(statement) }
            var rows: [[String: String]] = []; var result: Int32
            repeat {
                result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    var row: [String: String] = [:]
                    for column in 0..<sqlite3_column_count(statement) {
                        if let name = sqlite3_column_name(statement, column), let value = sqlite3_column_text(statement, column) {
                            row[String(cString: name)] = String(cString: value)
                        }
                    }; rows.append(row)
                }
            } while result == SQLITE_ROW && rows.count < 2000
            guard result == SQLITE_DONE else { throw LumeError.message("Não foi possível ler a configuração completa.") }; return rows
        }
        let meshes = try query("SELECT * FROM mesh")
        guard meshes.count == 1, let mesh = meshes.first else { throw LumeError.message("Há mais de uma rede neste arquivo. Importe uma exportação JSON da luz desejada.") }
        let rows = try query("SELECT mac_address, node_address, name FROM fixtures WHERE node_address > 1")
        return try rows.map { row in
            guard let addr = UInt16(row["node_address"] ?? "") else { throw LumeError.message("Endereço da luz inválido.") }
            return try LightConfiguration(name: row["name"] ?? "amaran 60x S", netKey: mesh["net_key"] ?? "", appKey: mesh["app_key"] ?? "", address: addr).validated()
        }
    }
    static func localDatabases() -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/amaran Desktop")
        guard let folders = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return [] }
        return folders.map { $0.appendingPathComponent("amaran.db") }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum CredentialStore {
    private static let service = "dev.jonatas.lume.bluetooth"
    static func load() throws -> LightConfiguration? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: "light", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LumeError.message("Não foi possível acessar a configuração no Chaves do macOS.") }
        return try JSONDecoder().decode(LightConfiguration.self, from: data).validated()
    }
    static func save(_ config: LightConfiguration) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "light"]
        let data = try JSONEncoder().encode(config)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw LumeError.message("Não foi possível salvar a configuração no Chaves.") }; return
        }
        guard status == errSecSuccess else { throw LumeError.message("Não foi possível atualizar a configuração no Chaves.") }
    }
}

// Each installation uses its own unicast source, never the phone's 0x0001.
// The sequence is reserved on disk BEFORE any BLE write, including after a crash.
final class SequenceStore {
    struct State: Codable { var source: UInt16; var next: UInt32; var iv: UInt32 }
    let url: URL
    private(set) var state: State
    init(network: String, occupied: [UInt16], directory: URL? = nil) throws {
        let folder = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Lume")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        url = folder.appendingPathComponent("sequence-\(network).json")
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            guard (0x7000...0x7ffe).contains(state.source), state.next <= 0xffffff, !occupied.contains(state.source) else {
                throw LumeError.message("A configuração de conexão precisa ser revisada antes de continuar.")
            }
        } else {
            let available = (0x7000...0x7ffe).compactMap { UInt16($0) }.filter { !occupied.contains($0) }
            guard let address = available.randomElement() else { throw LumeError.message("Não há endereço de conexão disponível.") }
            state = State(source: address, next: 0, iv: 0); try persist()
        }
    }
    private func persist() throws {
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func take() throws -> UInt32 {
        guard state.next < 0xffffff else { throw LumeError.message("O limite de comandos desta conexão foi atingido. Reconfigure a conexão.") }
        let value = state.next; state.next += 1
        // A failed write must prevent the caller from sending with an unreserved number.
        try persist(); return value
    }
    func updateIV(_ iv: UInt32) throws {
        guard iv >= state.iv else { throw LumeError.message("Estado Bluetooth anterior ao salvo. Reconecte a luz.") }
        state.iv = iv; try persist()
    }
}

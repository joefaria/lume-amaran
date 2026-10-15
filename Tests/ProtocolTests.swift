import Foundation
import SQLite3
import CryptoKit

@main struct ProtocolTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw LumeError.message("FAIL: \(name)") }; count += 1
    }
    static func rejects(_ name: String, _ body: () throws -> Void) throws {
        do { try body() } catch { count += 1; return }; throw LumeError.message("FAIL: \(name) should reject")
    }
    static func main() throws {
        let key = try Bytes(hex: "2b7e151628aed2a6abf7158809cf4f3c")
        // NIST SP 800-38B CMAC examples: empty, full block, partial final block.
        try check(MeshCrypto.cmac(key, []).hex == "bb1d6929e95937287fa37d129b756746", "NIST CMAC empty")
        try check(MeshCrypto.cmac(key, Bytes(hex: "6bc1bee22e409f96e93d7e117393172a")).hex == "070a16b46b4d4144f79bdd9dd04a287c", "NIST CMAC block")
        try check(MeshCrypto.cmac(key, Bytes(hex: "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411")).hex == "dfa66747de9ae63030ca32611497c827", "NIST CMAC partial")
        try check(Telink.power(true).hex == "8d00000000000000018c", "captured ON")
        try check(Telink.power(false).hex == "8c00000000000000008c", "captured OFF")
        try check(Telink.brightness(10).hex == "a800000000000000198f", "captured dimmer 10")
        try check(Telink.brightness(50).hex == "0c000000000000007d8f", "captured dimmer 50")
        try check(Telink.cct(3200, brightness: 22).hex == "0e000000004001143782", "captured CCT 3200")
        try check(Telink.cct(5600, brightness: 30).hex == "31000000004001234b82", "captured CCT 5600")
        try check(Telink.brightness(-100) == Telink.brightness(0), "brightness lower bound")
        try check(Telink.brightness(200) == Telink.brightness(100), "brightness upper bound")
        try check(Telink.cct(2000, brightness: 50) == Telink.cct(2700, brightness: 50), "60x S minimum")
        try check(Telink.cct(9000, brightness: 50) == Telink.cct(6500, brightness: 50), "60x S maximum")
        let net = try Bytes(hex: "00112233445566778899aabbccddeeff")
        let app = try Bytes(hex: "ffeeddccbbaa99887766554433221100")
        let mesh = try Mesh(net: net, app: app)
        let vectors = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: String]
        try check(mesh.networkID.hex == vectors["network"], "network ID matches independent Node crypto")
        let nonce = try Bytes(hex: "01000000017000000200000000")
        let access = [UInt8(0x26)] + Telink.power(true)
        for mic in [4, 8] {
            let encrypted = try MeshCrypto.encrypt(app, nonce, access, mic: mic)
            try check(encrypted.hex == vectors["ccm\(mic)"], "AES-CCM \(mic)-byte MIC parity")
            try check(MeshCrypto.decrypt(app, nonce, encrypted, mic: mic) == access, "AES-CCM \(mic) roundtrip")
            var corrupt = encrypted; corrupt[0] ^= 1
            try rejects("CCM tamper") { _ = try MeshCrypto.decrypt(app, nonce, corrupt, mic: mic) }
        }
        var report = Telink.cct(4300, brightness: 65); report[1] = 1; report[9] = 2; report = Telink.finish(report)
        try check(Telink.decode(report) == LightStatus(on: true, brightness: 65, kelvin: 4300), "actual status decoder")
        report[0] ^= 1; try check(Telink.decode(report) == nil, "reject corrupted status")
        let packet = try mesh.packet(Telink.power(true), sequence: 1, source: 0x7000, target: 2, iv: 0)
        try check(packet.hex == vectors["packet"], "full packet parity with independent Node crypto")
        let filter = try mesh.filter(sequence: 2, source: 0x7000, iv: 0)
        try check(filter.hex == vectors["filter"], "filter uses 64-bit NetMIC")
        let (_, seq, src, plain) = try mesh.decodeNetwork(filter, iv: 0)
        try check(seq == 2 && src == 0x7000 && plain == [0,0,0,1], "authenticated filter decoding")
        var corrupt = filter; corrupt[corrupt.count - 1] ^= 0xff
        try rejects("network authentication") { _ = try mesh.decodeNetwork(corrupt, iv: 0) }
        let beaconMesh = try Mesh(net: Bytes(hex: "7dd7364cd842ad18c17c2b820c84c3d6"), app: app)
        let beacon = try Bytes(hex: "0101003ecaff672f673370123456788ea261582f364f6f")
        try check(beaconMesh.beacon(beacon)?.0 == 0x12345678, "Bluetooth Mesh authenticated beacon vector")
        var alteredBeacon = beacon; alteredBeacon[14] ^= 1
        try check(beaconMesh.beacon(alteredBeacon) == nil, "reject forged IV beacon")
        let json = Data("{\"netKey\":\"\(net.hex)\",\"appKey\":\"\(app.hex)\",\"lights\":[{\"name\":\"60x S\",\"address\":2}]}".utf8)
        try check(ConfigurationImport.json(json).first?.address == 2, "import CLI JSON")
        let haJSON = Data("{\"net_key\":\"\(net.hex)\",\"app_key\":\"\(app.hex)\",\"fixtures\":[{\"name\":\"60x S\",\"node_address\":2}]}".utf8)
        try check(ConfigurationImport.json(haJSON).first?.name == "60x S", "import HACS JSON")
        let sidusJSON = Data("{\"netKeys\":[{\"key\":\"\(net.hex)\"}],\"appKeys\":[{\"key\":\"\(app.hex)\"}],\"nodes\":[{\"name\":\"ItonMeshProvisioner\",\"unicastAddress\":\"0001\"},{\"name\":\"amaran 60x S\",\"unicastAddress\":\"000a\"}]}".utf8)
        let sidus = try ConfigurationImport.json(sidusJSON)
        try check(sidus.count == 1 && sidus[0].address == 10, "Sidus iOS import uses hex addresses, excludes provisioner")
        try rejects("bad key") { _ = try LightConfiguration(name: "test", netKey: "bad", appKey: app.hex, address: 2).validated() }
        try rejects("bad hex") { _ = try Bytes(hex: "00zz") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SequenceStore(network: mesh.networkID.hex, occupied: [2], directory: folder)
        let source = store.state.source
        try check((0x7000...0x7ffe).contains(source), "dedicated source never uses phone address")
        try check(store.take() == 0, "first reserved sequence")
        try check(store.take() == 1, "second reserved sequence")
        let restored = try SequenceStore(network: mesh.networkID.hex, occupied: [2], directory: folder)
        try check(restored.state.source == source && restored.take() == 2, "no sequence reuse across restart")
        try restored.updateIV(5)
        try rejects("IV rollback") { try restored.updateIV(4) }
        let mode = try FileManager.default.attributesOfItem(atPath: restored.url.path)[.posixPermissions] as? NSNumber
        try check(mode?.intValue == 0o600, "private sequence store")
        try Data("corrupt".utf8).write(to: restored.url)
        try rejects("corrupt sequence state never resets") { _ = try SequenceStore(network: mesh.networkID.hex, occupied: [2], directory: folder) }
        let dbPath = folder.appendingPathComponent("sample.db").path; var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_exec(db, "CREATE TABLE mesh(net_key TEXT,app_key TEXT); CREATE TABLE fixtures(mac_address TEXT,node_address INTEGER,name TEXT); INSERT INTO mesh VALUES('\(net.hex)','\(app.hex)'); INSERT INTO fixtures VALUES('00:00:00:00:00:01',2,'60x S');", nil, nil, nil)
        sqlite3_close(db)
        try check(ConfigurationImport.database(dbPath).first?.address == 2, "read-only Desktop DB import")
        let backup = folder.appendingPathComponent("iphone"); try FileManager.default.createDirectory(at: backup.appendingPathComponent("ab"), withIntermediateDirectories: true)
        let fileID = "ab" + String(repeating: "c", count: 38)
        try sidusJSON.write(to: backup.appendingPathComponent("ab/\(fileID)"))
        sqlite3_open(backup.appendingPathComponent("Manifest.db").path, &db)
        sqlite3_exec(db, "CREATE TABLE Files(fileID TEXT,domain TEXT,relativePath TEXT,flags INTEGER); INSERT INTO Files VALUES('\(fileID)','AppDomain-com.aputure.cn.SidusLink','Documents/mesh/test.json',1); INSERT INTO Files VALUES('../private','AppDomain-unrelated','Documents/mesh/private.json',1);", nil, nil, nil)
        sqlite3_close(db)
        try check(ConfigurationImport.iphoneBackup(backup).first?.address == 10, "iPhone backup reads only Sidus lighting files")
        try PropertyListSerialization.data(fromPropertyList: ["IsEncrypted": true], format: .binary, options: 0).write(to: backup.appendingPathComponent("Manifest.plist"))
        try rejects("encrypted backup fails explicitly") { _ = try ConfigurationImport.iphoneBackup(backup) }
        // Complete two-party PB-GATT transcript, without any BLE hardware.
        let session = try LightPairing()
        try check(session.invite() == [0, 0], "provisioning invite")
        let caps: Bytes = [1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
        let started = try session.receive(caps)
        try check(started.count == 2 && started[0] == [2, 0, 0, 0, 0, 0] && started[1].count == 65, "provisioning start and public key")
        let peer = P256.KeyAgreement.PrivateKey()
        let peerPublic = Bytes(peer.publicKey.x963Representation.dropFirst())
        let macPublic = try P256.KeyAgreement.PublicKey(x963Representation: Data([4] + session.publicKey))
        let shared = try peer.sharedSecretFromKeyAgreement(with: macPublic)
        let secret = shared.withUnsafeBytes { Bytes($0) }
        let transcript = [UInt8(0)] + Array(caps.dropFirst()) + Array(started[0].dropFirst()) + session.publicKey + peerPublic
        let salt = try MeshCrypto.s1(transcript)
        let confirmationKey = try MeshCrypto.k1(secret, salt, Bytes("prck".utf8))
        let provisionerConfirmation = try session.receive([3] + peerPublic)
        try check(provisionerConfirmation == [[5] + MeshCrypto.cmac(confirmationKey, session.random + MeshCrypto.zero)], "peer verifies provisioner confirmation")
        let peerRandom = try Bytes(hex: "55a2a2bca04cd32ff6f346bd0a0c1a3a")
        let confirmation = try MeshCrypto.cmac(confirmationKey, peerRandom + MeshCrypto.zero)
        try check(session.receive([5] + confirmation) == [[6] + session.random], "provisioner reveals random only after commitment")
        let data = try session.receive([6] + peerRandom)
        let provisioningSalt = try MeshCrypto.s1(salt + session.random + peerRandom)
        let sessionKey = try MeshCrypto.k1(secret, provisioningSalt, Bytes("prsk".utf8))
        let sessionNonce = Array(try MeshCrypto.k1(secret, provisioningSalt, Bytes("prsn".utf8)).suffix(13))
        let provisioned = try MeshCrypto.decrypt(sessionKey, sessionNonce, Array(data[0].dropFirst()), mic: 8)
        try check(provisioned == session.netKey + [0,0,0,0,0,0,0,0,2], "peer decrypts complete provisioning data")
        try check(session.deviceKey == MeshCrypto.k1(secret, provisioningSalt, Bytes("prdk".utf8)), "shared DeviceKey derived correctly")
        try check(session.receive([8]).isEmpty && session.stage == .done, "pairing requires Complete PDU")
        try rejects("completed session cannot repeat") { _ = try session.receive([8]) }
        let bad = try LightPairing(); _ = try bad.invite(); _ = try bad.receive(caps); _ = try bad.receive([3] + peerPublic)
        _ = try bad.receive([5] + Bytes(repeating: 0, count: 16))
        try rejects("forged pairing confirmation") { _ = try bad.receive([6] + peerRandom) }
        try check(bad.deviceKey == nil, "no network or DeviceKey committed on authentication failure")
        let order = try LightPairing(); _ = try order.invite()
        try rejects("pairing state machine rejects out-of-order random") { _ = try order.receive([6] + peerRandom) }
        // Fixed Bluetooth Mesh sample data, independent of generated key pairs.
        let sampleSecret = try Bytes(hex: "ab85843a2f6d883f62e5684b38e307335fe6e1945ecd19604105c6f23221eb69")
        let sampleSalt = try Bytes(hex: "5faabe187337c71cc6c973369dcaa79a")
        try check(MeshCrypto.k1(sampleSecret, sampleSalt, Bytes("prck".utf8)).hex == "e31fe046c68ec339c425fc6629f0336f", "Bluetooth Mesh sample confirmation key")
        let sampleP = try Bytes(hex: "8b19ac31d58b124c946209b5db1021b9")
        let sampleProvisionSalt = try MeshCrypto.s1(sampleSalt + sampleP + peerRandom)
        try check(sampleProvisionSalt.hex == "a21c7d45f201cf9489a2fb57145015b4", "Bluetooth Mesh sample provisioning salt")
        try check(MeshCrypto.k1(sampleSecret, sampleProvisionSalt, Bytes("prdk".utf8)).hex == "0520adad5e0142aa3e325087b4ec16d8", "Bluetooth Mesh sample DeviceKey")
        let deviceKey = try Bytes(hex: "0520adad5e0142aa3e325087b4ec16d8")
        let addKey = [UInt8(0),0,0,0] + app
        let segmented = try mesh.devicePackets(addKey, deviceKey: deviceKey, sequences: [0x1fff, 0x2000], source: 0x7000, target: 2, iv: 0)
        try check(segmented.count == 2, "AppKey Add uses two network segments")
        let receiver = DeviceAccessReceiver()
        try check(receiver.receive(segmented[1], mesh: mesh, deviceKey: deviceKey, iv: 0, target: 0x7000, source: 2) == nil, "out-of-order segmented receive waits for all data")
        let reassembled = try receiver.receive(segmented[0], mesh: mesh, deviceKey: deviceKey, iv: 0, target: 0x7000, source: 2)
        try check(reassembled?.access == addKey && reassembled?.ack == 0x1fff && reassembled?.block == 3, "segmented DeviceKey decrypt across sequence boundary")
        let ack = try mesh.acknowledgement(zero: 0x1fff, block: 3, sequence: 5, source: 2, target: 0x7000, iv: 0)
        let (ctl, _, _, ackPlain) = try mesh.decodeNetwork(ack, iv: 0)
        try check(ctl & 0x80 != 0 && ackPlain == [0x70,0,0,0x7f,0xfc,0,0,0,3], "authenticated segment acknowledgement with 64-bit NetMIC")
        let composition: Bytes = [2,0,0x11,2,1,0,1,0,8,0,3,0, 0,0,1,1, 0,0, 0x11,2,1,0]
        let binding = try VendorBinding.fromComposition(composition, primary: 2)
        try check(binding.message == [0x80,0x3d,2,0,0,0,0x11,2,1,0], "vendor binding from actual composition layout")
        try check(binding.matches([0x80,0x3e,0,2,0,0,0,0x11,2,1,0]), "successful vendor binding status validated")
        try check(!binding.matches([0x80,0x3e,1,2,0,0,0,0x11,2,1,0]), "rejected binding never becomes ready")
        try rejects("truncated composition") { _ = try VendorBinding.fromComposition(Array(composition.dropLast()), primary: 2) }
        // Simulate delayed and stale responses while a user edits both sliders.
        // CCT packets include brightness: serializing without merging would
        // otherwise restore the old intensity when changing temperature.
        let initial = LightStatus(on: true, brightness: 20, kelvin: 4500)
        var controls = LightControlPipeline()
        controls.enqueue(.brightness(30))
        let first = controls.takeNext(confirmed: initial)!
        controls.enqueue(.temperature(5000)); controls.enqueue(.brightness(40))
        controls.enqueue(.temperature(5600)); controls.enqueue(.brightness(50))
        try check(controls.takeNext(confirmed: initial) == nil, "only one light command in flight")
        try check(!controls.acknowledge(initial), "old brightness report cannot release the next command")
        try check(controls.holdsBrightness && controls.holdsKelvin, "both outstanding slider values stay protected")
        try check(controls.acknowledge(first.target) && controls.pending, "first confirmation preserves newer user input")
        let combined = controls.takeNext(confirmed: first.target)!
        try check(combined.target == LightStatus(on: true, brightness: 50, kelvin: 5600), "latest brightness and CCT coalesce across controls")
        try check(combined.payload == Telink.cct(5600, brightness: 50), "CCT packet never restores obsolete brightness")
        try check(!controls.acknowledge(first.target), "late acknowledgement cannot finish newer adjustment")
        try check(!controls.acknowledge(LightStatus(on: true, brightness: 50, kelvin: 5500)), "neighboring 100K step is not mistaken for the target")
        try check(controls.acknowledge(combined.target) && !controls.pending, "latest combined target confirmed without extra sends")
        try check(!controls.holdsBrightness && !controls.holdsKelvin, "confirmed sliders resume normal state sync")

        controls.enqueue(.temperature(3200))
        let temperature = controls.takeNext(confirmed: initial)!
        controls.enqueue(.brightness(65))
        try check(controls.acknowledge(temperature.target), "temperature-first adjustment confirmed")
        let intensity = controls.takeNext(confirmed: temperature.target)!
        try check(intensity.kind == .brightness && intensity.target.kelvin == 3200 && intensity.target.brightness == 65,
                  "brightness arriving during CCT preserves the confirmed new temperature")
        try check(controls.acknowledge(intensity.target) && !controls.pending, "reverse control order drains correctly")

        controls.enqueue(.brightness(1)); let earliest = controls.takeNext(confirmed: initial)!
        for value in 2...100 { controls.enqueue(.brightness(Double(value))) }
        try check(controls.acknowledge(earliest.target), "first of rapid slider updates confirmed")
        let latest = controls.takeNext(confirmed: earliest.target)!
        try check(latest.target.brightness == 100, "rapid input retains only the latest unsent value")
        try check(controls.acknowledge(latest.target) && controls.takeNext(confirmed: latest.target) == nil,
                  "rapid input does not build an obsolete command backlog")

        let off = LightStatus(on: false, brightness: 20, kelvin: 4500)
        controls.enqueue(.power(true)); let turnOn = controls.takeNext(confirmed: off)!
        controls.enqueue(.power(false))
        try check(controls.requestedPower == false, "rapid power toggle uses the latest requested state")
        try check(controls.acknowledge(turnOn.target), "power-on confirmation keeps queued power-off")
        let turnOff = controls.takeNext(confirmed: turnOn.target)!
        try check(turnOff.target.on == false && controls.acknowledge(turnOff.target), "power-off drains after power-on")

        controls.enqueue(.preset(kelvin: 3200, brightness: 25))
        let preset = controls.takeNext(confirmed: initial)!
        controls.enqueue(.preset(kelvin: 5600, brightness: 75)); controls.enqueue(.temperature(5000))
        try check(controls.acknowledge(preset.target), "preset confirmation preserves later intent")
        let updatedPreset = controls.takeNext(confirmed: preset.target)!
        try check(updatedPreset.target == LightStatus(on: true, brightness: 75, kelvin: 5000), "slider overrides only its own preset field")
        controls.enqueue(.brightness(99)); controls.cancel()
        try check(!controls.pending && !controls.holdsBrightness && !controls.holdsKelvin && controls.requestedPower == nil,
                  "disconnect or timeout discards all in-flight and unsent intent")
        try check(controls.takeNext(confirmed: initial) == nil && !controls.acknowledge(updatedPreset.target),
                  "late response after cancellation cannot restart old commands")
        controls.enqueue(.preset(kelvin: 9000, brightness: 150))
        let bounded = controls.takeNext(confirmed: initial)!
        try check(bounded.target.kelvin == 6500 && bounded.target.brightness == 100, "confirmation target uses the fixture limits")
        print("PASS: \(count) protocol, authentication, import, persistence and control sequencing checks")
    }
}

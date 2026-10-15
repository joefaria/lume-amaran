// Protocol adapted from wesbos/amaran-BLE-control and neyako/amaran-hacs (MIT).
import Foundation
import CommonCrypto

enum LumeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
typealias Bytes = [UInt8]
extension Array where Element == UInt8 {
    init(hex: String) throws {
        let s = hex.filter { !$0.isWhitespace && $0 != ":" && $0 != "-" }
        guard s.count % 2 == 0, s.count <= 4096 else { throw LumeError.message("Configuração inválida.") }
        var out: Bytes = []; var index = s.startIndex
        while index < s.endIndex {
            let end = s.index(index, offsetBy: 2)
            guard let b = UInt8(s[index..<end], radix: 16) else { throw LumeError.message("Configuração inválida.") }
            out.append(b); index = end
        }
        self = out
    }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
func be(_ value: UInt32, _ count: Int) -> Bytes { (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
func integer(_ bytes: ArraySlice<UInt8>) -> UInt32 { bytes.reduce(0) { ($0 << 8) | UInt32($1) } }

enum MeshCrypto {
    static let zero = Bytes(repeating: 0, count: 16)
    static func aes(_ key: Bytes, _ block: Bytes) throws -> Bytes {
        guard key.count == 16, block.count == 16 else { throw LumeError.message("Bloco criptográfico inválido.") }
        var out = Bytes(repeating: 0, count: 32); var length = 0
        let status = key.withUnsafeBytes { k in block.withUnsafeBytes { b in out.withUnsafeMutableBytes { o in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode), k.baseAddress, 16, nil, b.baseAddress, 16, o.baseAddress, 32, &length)
        } } }
        guard status == kCCSuccess else { throw LumeError.message("Falha de criptografia.") }
        return Array(out.prefix(length))
    }
    static func xor(_ a: Bytes, _ b: Bytes) -> Bytes { zip(a, b).map { $0 ^ $1 } }
    static func shift(_ input: Bytes) -> Bytes {
        var b = input; var carry: UInt8 = 0
        for i in stride(from: 15, through: 0, by: -1) { let next = b[i] >> 7; b[i] = (b[i] << 1) | carry; carry = next }
        if input[0] & 0x80 != 0 { b[15] ^= 0x87 }; return b
    }
    static func cmac(_ key: Bytes, _ data: Bytes) throws -> Bytes {
        let k1 = shift(try aes(key, zero)); let k2 = shift(k1)
        let n = max(1, (data.count + 15) / 16); var state = zero
        if n > 1 { for i in 0..<(n - 1) { state = try aes(key, xor(state, Array(data[i * 16..<(i + 1) * 16]))) } }
        var last = Array(data.dropFirst((n - 1) * 16))
        if last.count == 16 { last = xor(last, k1) }
        else { last.append(0x80); last += Bytes(repeating: 0, count: 16 - last.count); last = xor(last, k2) }
        return try aes(key, xor(state, last))
    }
    static func s1(_ data: Bytes) throws -> Bytes { try cmac(zero, data) }
    static func k1(_ n: Bytes, _ salt: Bytes, _ p: Bytes) throws -> Bytes { try cmac(cmac(salt, n), p) }
    static func k3(_ key: Bytes) throws -> Bytes {
        let t = try cmac(s1(Bytes("smk3".utf8)), key)
        return Array(try cmac(t, Bytes("id64".utf8) + [1]).suffix(8))
    }
    static func tag(_ key: Bytes, _ nonce: Bytes, _ plain: Bytes, _ size: Int) throws -> Bytes {
        guard nonce.count == 13, [4, 8].contains(size), plain.count < 65536 else { throw LumeError.message("Mensagem criptográfica inválida.") }
        var state = try aes(key, [UInt8(((size - 2) / 2) << 3) | 1] + nonce + be(UInt32(plain.count), 2))
        for start in stride(from: 0, to: plain.count, by: 16) {
            var block = Array(plain[start..<min(start + 16, plain.count)])
            block += Bytes(repeating: 0, count: 16 - block.count)
            state = try aes(key, xor(state, block))
        }
        return Array(state.prefix(size))
    }
    static func ctr(_ key: Bytes, _ nonce: Bytes, _ data: Bytes) throws -> Bytes {
        var out: Bytes = []
        for start in stride(from: 0, to: data.count, by: 16) {
            let stream = try aes(key, [1] + nonce + be(UInt32(start / 16 + 1), 2))
            out += xor(Array(data[start..<min(start + 16, data.count)]), stream)
        }; return out
    }
    static func encrypt(_ key: Bytes, _ nonce: Bytes, _ plain: Bytes, mic: Int) throws -> Bytes {
        let t = try tag(key, nonce, plain, mic); let s0 = try aes(key, [1] + nonce + [0, 0])
        return try ctr(key, nonce, plain) + xor(t, s0)
    }
    static func decrypt(_ key: Bytes, _ nonce: Bytes, _ encrypted: Bytes, mic: Int) throws -> Bytes {
        guard encrypted.count >= mic else { throw LumeError.message("Mensagem incompleta.") }
        let plain = try ctr(key, nonce, Array(encrypted.dropLast(mic)))
        let expected = try xor(tag(key, nonce, plain, mic), aes(key, [1] + nonce + [0, 0]))
        var difference: UInt8 = 0
        for (a, b) in zip(expected, encrypted.suffix(mic)) { difference |= a ^ b }
        guard difference == 0 else { throw LumeError.message("Mensagem não autenticada.") }; return plain
    }
}

struct LightStatus: Equatable {
    let on: Bool
    let brightness: Double
    let kelvin: Double
}
enum Telink {
    static func finish(_ input: Bytes) -> Bytes { var p = input; p[0] = UInt8(truncatingIfNeeded: p.dropFirst().reduce(0) { $0 + Int($1) }); return p }
    static func power(_ on: Bool) -> Bytes { var p = Bytes(repeating: 0, count: 10); p[8] = on ? 1 : 0; p[9] = 0x8c; return finish(p) }
    static func status() -> Bytes { var p = Bytes(repeating: 0, count: 10); p[9] = 0x0e; return finish(p) }
    static func brightness(_ percent: Double) -> Bytes {
        let v = Int((min(100, max(0, percent)) * 10).rounded())
        var p = Bytes(repeating: 0, count: 10); p[7] = UInt8((v & 3) << 6); p[8] = UInt8(v >> 2); p[9] = 0x8f; return finish(p)
    }
    static func cct(_ kelvin: Double, brightness: Double) -> Bytes {
        let v = Int((min(100, max(0, brightness)) * 10).rounded())
        let cct = UInt64((Int(min(6500, max(2700, kelvin))) + 5) / 10)
        let low = (UInt64(v & 3) << 62) | (cct << 52) | (UInt64(10) << 45)
        var p = (0..<8).map { UInt8(truncatingIfNeeded: low >> ($0 * 8)) }
        p += [UInt8(v >> 2), 0x82]; return finish(p)
    }
    static func decode(_ p: Bytes) -> LightStatus? {
        guard p.count == 10, finish(p)[0] == p[0], p[9] & 0x7f == 2 else { return nil }
        let low = (0..<8).reduce(UInt64(0)) { $0 | (UInt64(p[$1]) << ($1 * 8)) }
        let cct = Int((low >> 52) & 0x3ff) + (((low >> 42) & 1) != 0 ? 1000 : 0)
        let v = (Int(p[8]) << 2) | Int((low >> 62) & 3)
        guard v <= 1000, (270...650).contains(cct) else { return nil }
        return LightStatus(on: (low >> 8) & 1 != 0, brightness: Double(v) / 10, kelvin: Double(cct * 10))
    }
}

struct Mesh {
    let netKey: Bytes; let appKey: Bytes
    let nid: UInt8; let aid: UInt8; let encryption: Bytes; let privacy: Bytes; let networkID: Bytes; let beaconKey: Bytes
    init(net: Bytes, app: Bytes) throws {
        guard net.count == 16, app.count == 16 else { throw LumeError.message("Chaves Bluetooth inválidas.") }
        netKey = net; appKey = app
        let t = try MeshCrypto.cmac(MeshCrypto.s1(Bytes("smk2".utf8)), net)
        let t1 = try MeshCrypto.cmac(t, [0, 1]); let t2 = try MeshCrypto.cmac(t, t1 + [0, 2])
        nid = t1[15] & 0x7f; encryption = t2; privacy = try MeshCrypto.cmac(t, t2 + [0, 3])
        let t4 = try MeshCrypto.cmac(MeshCrypto.s1(Bytes("smk4".utf8)), app)
        aid = try MeshCrypto.cmac(t4, Bytes("id6".utf8) + [1])[15] & 0x3f
        networkID = try MeshCrypto.k3(net)
        beaconKey = try MeshCrypto.k1(net, MeshCrypto.s1(Bytes("nkbk".utf8)), Bytes("id128".utf8) + [1])
    }
    func network(_ plain: Bytes, sequence: UInt32, source: UInt16, iv: UInt32, proxy: Bool, control: Bool = false) throws -> Bytes {
        let ctl: UInt8 = proxy ? 0x80 : (control ? 0x87 : 7)
        let nonce: Bytes = [proxy ? 3 : 0, proxy ? 0 : ctl] + be(sequence, 3) + be(UInt32(source), 2) + [0, 0] + be(iv, 4)
        let encrypted = try MeshCrypto.encrypt(encryption, nonce, plain, mic: proxy || control ? 8 : 4)
        let pecb = try MeshCrypto.aes(privacy, Bytes(repeating: 0, count: 5) + be(iv, 4) + Array(encrypted.prefix(7)))
        let header = [ctl] + be(sequence, 3) + be(UInt32(source), 2)
        return [proxy ? 2 : 0, UInt8((iv & 1) << 7) | nid] + MeshCrypto.xor(header, pecb) + encrypted
    }
    func packet(_ payload: Bytes, sequence: UInt32, source: UInt16, target: UInt16, iv: UInt32) throws -> Bytes {
        let nonce: Bytes = [1, 0] + be(sequence, 3) + be(UInt32(source), 2) + be(UInt32(target), 2) + be(iv, 4)
        let access = try MeshCrypto.encrypt(appKey, nonce, [0x26] + payload, mic: 4)
        return try network(be(UInt32(target), 2) + [0x40 | aid] + access, sequence: sequence, source: source, iv: iv, proxy: false)
    }
    func filter(sequence: UInt32, source: UInt16, iv: UInt32) throws -> Bytes {
        try network([0, 0, 0, 1], sequence: sequence, source: source, iv: iv, proxy: true)
    }
    func decodeNetwork(_ p: Bytes, iv: UInt32) throws -> (UInt8, UInt32, UInt16, Bytes) {
        guard p.count >= 16, [UInt8(0), 2].contains(p[0]), p[1] & 0x7f == nid else { throw LumeError.message("Mensagem de outra rede.") }
        let encrypted = Array(p.dropFirst(8))
        let pecb = try MeshCrypto.aes(privacy, Bytes(repeating: 0, count: 5) + be(iv, 4) + Array(encrypted.prefix(7)))
        let h = MeshCrypto.xor(Array(p[2..<8]), pecb)
        let seq = integer(h[1..<4]); let src = UInt16(integer(h[4..<6]))
        let proxy = p[0] == 2; let ctl = h[0] & 0x80 != 0
        guard (proxy && h[0] == 0x80) || !proxy else { throw LumeError.message("Mensagem não suportada.") }
        let nonce = [UInt8(proxy ? 3 : 0), proxy ? 0 : h[0]] + Array(h[1..<6]) + [0, 0] + be(iv, 4)
        return (h[0], seq, src, try MeshCrypto.decrypt(encryption, nonce, encrypted, mic: ctl ? 8 : 4))
    }
    func status(_ p: Bytes, iv: UInt32, target: UInt16) -> LightStatus? {
        var receivedIV = iv
        guard p.count > 1 else { return nil }
        if p[1] >> 7 != UInt8(iv & 1) { guard iv > 0 else { return nil }; receivedIV -= 1 }
        guard let (_, seq, src, plain) = try? decodeNetwork(p, iv: receivedIV), src == target,
              plain.count >= 8, plain[2] & 0xc0 == 0x40, plain[2] & 0x3f == aid else { return nil }
        let nonce = [UInt8(1), 0] + be(seq, 3) + be(UInt32(src), 2) + Array(plain[0..<2]) + be(receivedIV, 4)
        guard let access = try? MeshCrypto.decrypt(appKey, nonce, Array(plain.dropFirst(3)), mic: 4), access.count == 11, access[0] == 0x26 else { return nil }
        return Telink.decode(Array(access.dropFirst()))
    }
    func beacon(_ p: Bytes) -> (UInt32, Bool)? {
        guard p.count == 23, p[0] == 1, p[1] == 1, Array(p[3..<11]) == networkID,
              let auth = try? MeshCrypto.cmac(beaconKey, Array(p[2..<15])), Array(auth.prefix(8)) == Array(p[15..<23]) else { return nil }
        return (integer(p[11..<15]), p[2] & 2 != 0)
    }
}

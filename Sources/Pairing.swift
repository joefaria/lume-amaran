import Foundation
import CryptoKit
import Security

/// PB-GATT provisioning, Bluetooth Mesh Profile 1.0.1 §5.4.
/// Algorithm 0, in-band P-256 public keys, no OOB (supported by 60x S).
final class LightPairing {
    enum Stage: Equatable { case idle, capabilities, publicKey, confirmation, random, complete, done }
    private(set) var stage: Stage = .idle
    let privateKey: P256.KeyAgreement.PrivateKey
    let random: Bytes
    let netKey: Bytes
    let appKey: Bytes
    let address: UInt16 = 2
    private var capabilities: Bytes = []
    private var secret: Bytes = []
    private var confirmationSalt: Bytes = []
    private var confirmationKey: Bytes = []
    private var deviceConfirmation: Bytes = []
    private(set) var deviceKey: Bytes?
    private let start: Bytes = [2, 0, 0, 0, 0, 0]
    init() throws {
        privateKey = P256.KeyAgreement.PrivateKey()
        random = try Self.secureRandom(); netKey = try Self.secureRandom(); appKey = try Self.secureRandom()
    }
    static func secureRandom() throws -> Bytes {
        var bytes = Bytes(repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LumeError.message("Não foi possível criar uma conexão segura.") }
        return bytes
    }
    var publicKey: Bytes { Array(privateKey.publicKey.x963Representation.dropFirst()) }
    func invite() throws -> Bytes {
        guard stage == .idle else { throw LumeError.message("O pareamento já foi iniciado.") }
        stage = .capabilities; return [0, 0]
    }
    var progress: String {
        switch stage {
        case .idle, .capabilities: return "Identificando a luz…"
        case .publicKey: return "Criando conexão segura…"
        case .confirmation, .random: return "Confirmando pareamento…"
        case .complete: return "Salvando conexão na luz…"
        case .done: return "Pareamento concluído"
        }
    }
    func receive(_ pdu: Bytes) throws -> [Bytes] {
        guard let type = pdu.first else { throw LumeError.message("Resposta de pareamento vazia.") }
        if type == 9 {
            let code = pdu.count > 1 ? String(format: "%02x", pdu[1]) : "?"
            throw LumeError.message("A luz recusou o pareamento (código \(code)). Tente novamente com a luz próxima ao Mac.")
        }
        switch stage {
        case .capabilities:
            guard type == 1, pdu.count == 12, pdu[1] > 0, pdu[3] & 1 != 0 else {
                throw LumeError.message("Esta luz não oferece o método de pareamento esperado.")
            }
            capabilities = Array(pdu.dropFirst()); stage = .publicKey
            return [start, [3] + publicKey]
        case .publicKey:
            guard type == 3, pdu.count == 65 else { throw LumeError.message("Resposta de conexão segura inesperada.") }
            let peer = try P256.KeyAgreement.PublicKey(x963Representation: Data([4] + pdu.dropFirst()))
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
            secret = shared.withUnsafeBytes { Bytes($0) }
            let transcript: Bytes = [0] + capabilities + Array(start.dropFirst()) + publicKey + Array(pdu.dropFirst())
            confirmationSalt = try MeshCrypto.s1(transcript)
            confirmationKey = try MeshCrypto.k1(secret, confirmationSalt, Bytes("prck".utf8))
            let value = try MeshCrypto.cmac(confirmationKey, random + MeshCrypto.zero)
            stage = .confirmation; return [[5] + value]
        case .confirmation:
            guard type == 5, pdu.count == 17 else { throw LumeError.message("Confirmação de pareamento inesperada.") }
            deviceConfirmation = Array(pdu.dropFirst()); stage = .random
            return [[6] + random]
        case .random:
            guard type == 6, pdu.count == 17 else { throw LumeError.message("Resposta de autenticação inesperada.") }
            let deviceRandom = Array(pdu.dropFirst())
            let expected = try MeshCrypto.cmac(confirmationKey, deviceRandom + MeshCrypto.zero)
            var difference: UInt8 = 0
            for (a, b) in zip(expected, deviceConfirmation) { difference |= a ^ b }
            guard difference == 0 else { throw LumeError.message("A autenticação da luz falhou. Nenhuma configuração foi enviada.") }
            let salt = try MeshCrypto.s1(confirmationSalt + random + deviceRandom)
            let sessionKey = try MeshCrypto.k1(secret, salt, Bytes("prsk".utf8))
            let nonce = Array(try MeshCrypto.k1(secret, salt, Bytes("prsn".utf8)).suffix(13))
            deviceKey = try MeshCrypto.k1(secret, salt, Bytes("prdk".utf8))
            let data = netKey + [0, 0, 0] + be(0, 4) + be(UInt32(address), 2)
            let encrypted = try MeshCrypto.encrypt(sessionKey, nonce, data, mic: 8)
            stage = .complete; return [[7] + encrypted]
        case .complete:
            guard pdu == [8] else { throw LumeError.message("A luz ainda não confirmou o pareamento.") }
            stage = .done; return []
        default: throw LumeError.message("Resposta fora da etapa de pareamento esperada.")
        }
    }
}

func le16(_ n: UInt16) -> Bytes { [UInt8(truncatingIfNeeded: n), UInt8(n >> 8)] }
func little16(_ b: Bytes, _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }

struct VendorBinding: Equatable {
    let element: UInt16
    let company: UInt16
    let model: UInt16
    var message: Bytes { [0x80, 0x3d] + le16(element) + [0, 0] + le16(company) + le16(model) }
    func matches(_ pdu: Bytes) -> Bool {
        pdu.count == 11 && Array(pdu.prefix(2)) == [0x80, 0x3e] && pdu[2] == 0
            && little16(pdu, 3) == element && little16(pdu, 5) == 0
            && little16(pdu, 7) == company && little16(pdu, 9) == model
    }
    static func fromComposition(_ access: Bytes, primary: UInt16) throws -> VendorBinding {
        guard access.count >= 16, Array(access.prefix(2)) == [2, 0] else { throw LumeError.message("A luz retornou uma configuração de controle inesperada.") }
        var offset = 12; var elementOffset: UInt16 = 0
        while offset + 4 <= access.count {
            let sigCount = Int(access[offset + 2]); let vendorCount = Int(access[offset + 3])
            let vendorStart = offset + 4 + sigCount * 2; let end = vendorStart + vendorCount * 4
            guard end <= access.count else { throw LumeError.message("A configuração de controle da luz veio incompleta.") }
            if vendorCount > 0 {
                guard elementOffset == 0 else { throw LumeError.message("Esta organização de controles ainda não é suportada.") }
                return VendorBinding(element: primary, company: little16(access, vendorStart), model: little16(access, vendorStart + 2))
            }
            offset = end; elementOffset += 1
        }
        throw LumeError.message("Não encontrei o controle amaran esperado nesta luz.")
    }
}

/// Reassembles authenticated Network PDUs into a DeviceKey access message.
/// Only the target light is accepted; there are no app/device keys in logs.
final class DeviceAccessReceiver {
    struct Partial {
        let authSequence: UInt32; let count: Int; let header: UInt8; let iv: UInt32
        var segments: [Int: Bytes] = [:]
        let created = Date()
    }
    private var partials: [UInt32: Partial] = [:]
    func receive(_ pdu: Bytes, mesh: Mesh, deviceKey: Bytes, iv: UInt32, target: UInt16, source: UInt16) throws -> (access: Bytes, ack: UInt16?, block: UInt32)? {
        guard pdu.first == 0 else { return nil }
        let (ctl, seq, sender, plain) = try mesh.decodeNetwork(pdu, iv: iv)
        guard ctl & 0x80 == 0, sender == target, plain.count >= 4, integer(plain[0..<2]) == source else { return nil }
        let lower = Array(plain.dropFirst(2)); let h = lower[0]
        guard h & 0x7f == 0 else { return nil } // DeviceKey: AKF=0, AID=0.
        var authSeq = seq; var encrypted: Bytes; var ack: UInt16?; var block: UInt32 = 0
        if h & 0x80 != 0 {
            guard lower.count >= 5, lower[1] & 0x80 == 0 else { throw LumeError.message("Fragmento Bluetooth não suportado.") }
            let zero = (UInt16(lower[1] & 0x7f) << 6) | UInt16(lower[2] >> 2)
            let index = (Int(lower[2] & 3) << 3) | Int(lower[3] >> 5)
            let last = Int(lower[3] & 31)
            guard index <= last, lower.count <= 16, index == last || lower.count == 16 else { return nil }
            authSeq = (seq & 0xffe000) | UInt32(zero)
            if authSeq > seq { guard authSeq >= 8192 else { return nil }; authSeq -= 8192 }
            partials = partials.filter { Date().timeIntervalSince($0.value.created) < 10 }
            if partials[authSeq] == nil {
                guard partials.count < 8 else { return nil }
                partials[authSeq] = Partial(authSequence: authSeq, count: last + 1, header: h, iv: iv)
            }
            guard var state = partials[authSeq], state.count == last + 1, state.iv == iv else { return nil }
            let segment = Array(lower.dropFirst(4))
            if let existing = state.segments[index], existing != segment { return nil }
            state.segments[index] = segment; partials[authSeq] = state
            guard state.segments.count == state.count else { return nil }
            encrypted = (0..<state.count).flatMap { state.segments[$0] ?? [] }
            partials.removeValue(forKey: authSeq); ack = zero
            block = state.count == 32 ? UInt32.max : (UInt32(1) << state.count) - 1
        } else { encrypted = Array(lower.dropFirst()); ack = nil }
        let nonce = [UInt8(2), 0] + be(authSeq, 3) + be(UInt32(sender), 2) + be(UInt32(source), 2) + be(iv, 4)
        let access = try MeshCrypto.decrypt(deviceKey, nonce, encrypted, mic: 4)
        return (access, ack, block)
    }
}

extension Mesh {
    func devicePackets(_ access: Bytes, deviceKey: Bytes, sequences: [UInt32], source: UInt16, target: UInt16, iv: UInt32) throws -> [Bytes] {
        let needed = Self.devicePacketCount(access.count)
        guard (1...32).contains(needed), sequences.count == needed, let first = sequences.first,
              zip(sequences, sequences.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { throw LumeError.message("Contadores Bluetooth inválidos.") }
        let nonce = [UInt8(2), 0] + be(first, 3) + be(UInt32(source), 2) + be(UInt32(target), 2) + be(iv, 4)
        let encrypted = try MeshCrypto.encrypt(deviceKey, nonce, access, mic: 4)
        if needed == 1 { return [try network(be(UInt32(target), 2) + [0] + encrypted, sequence: first, source: source, iv: iv, proxy: false)] }
        let zero = first & 0x1fff
        return try (0..<needed).map { i in
            let header: Bytes = [0x80, UInt8(zero >> 6), UInt8((zero & 63) << 2) | UInt8(i >> 3), UInt8((i & 7) << 5) | UInt8(needed - 1)]
            let part = Array(encrypted[i * 12..<min(encrypted.count, (i + 1) * 12)])
            return try network(be(UInt32(target), 2) + header + part, sequence: sequences[i], source: source, iv: iv, proxy: false)
        }
    }
    static func devicePacketCount(_ accessLength: Int) -> Int { accessLength + 4 <= 15 ? 1 : (accessLength + 4 + 11) / 12 }
    func acknowledgement(zero: UInt16, block: UInt32, sequence: UInt32, source: UInt16, target: UInt16, iv: UInt32) throws -> Bytes {
        try network(be(UInt32(target), 2) + [0] + be(UInt32(zero) << 2, 2) + be(block, 4), sequence: sequence, source: source, iv: iv, proxy: false, control: true)
    }
}

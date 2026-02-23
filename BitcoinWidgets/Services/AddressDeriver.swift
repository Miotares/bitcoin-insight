//
//  AddressDeriver.swift
//  BitcoinWidgets
//
//  Requires: swift-secp256k1 by 21-DOT-DEV
//  Add via Xcode → File → Add Package Dependencies:
//  https://github.com/21-DOT-DEV/swift-secp256k1
//  Module name: P256K
//

import Foundation
import CryptoKit
import P256K

// MARK: - Address Deriver

struct AddressDeriver {

    enum DerivationError: Error, LocalizedError {
        case invalidBase58
        case invalidChecksum
        case invalidKeyLength
        case invalidFormat
        case derivationFailed(String)
        case unsupportedType

        var errorDescription: String? {
            switch self {
            case .invalidBase58: return "Invalid Base58 encoding"
            case .invalidChecksum: return "Invalid xpub checksum"
            case .invalidKeyLength: return "Invalid key length"
            case .invalidFormat: return "Invalid xpub format"
            case .derivationFailed(let msg): return "Derivation failed: \(msg)"
            case .unsupportedType: return "Unsupported wallet type"
            }
        }
    }

    // MARK: - BIP32 Extended Public Key

    struct ExtendedPublicKey {
        let version: Data          // 4 bytes
        let depth: UInt8
        let fingerprint: Data      // 4 bytes
        let childIndex: UInt32
        let chainCode: Data        // 32 bytes
        let publicKey: Data        // 33 bytes (compressed)
    }

    // MARK: - Public API

    /// Derive a Bitcoin address from an xpub/ypub/zpub at path m/chain/index
    static func deriveAddress(
        from xpub: String,
        chain: Int,
        index: Int,
        type: WalletType
    ) throws -> String {
        let ext = try parseExtendedPublicKey(xpub)

        // Derive m/chain
        let (chainKey, chainCode) = try deriveChildPublicKey(
            parentKey: ext.publicKey,
            chainCode: ext.chainCode,
            index: UInt32(chain)
        )

        // Derive m/chain/index
        let (indexKey, _) = try deriveChildPublicKey(
            parentKey: chainKey,
            chainCode: chainCode,
            index: UInt32(index)
        )

        return try address(from: indexKey, type: type)
    }

    /// Derive an address directly from a raw compressed public key (33 bytes)
    static func address(from publicKey: Data, type: WalletType) throws -> String {
        guard publicKey.count == 33 else { throw DerivationError.invalidKeyLength }
        let h160 = hash160(publicKey)
        switch type {
        case .xpub:
            return Base58Check.encode(payload: h160, version: 0x00)
        case .ypub:
            // P2SH-P2WPKH: redeemScript = OP_0 OP_PUSH20 <hash160(pubkey)>
            var redeemScript = Data([0x00, 0x14])
            redeemScript.append(h160)
            return Base58Check.encode(payload: hash160(redeemScript), version: 0x05)
        case .zpub:
            // P2WPKH: bech32 witness program
            return try Bech32.encode(hrp: "bc", witnessVersion: 0, program: h160)
        case .singleAddress:
            throw DerivationError.unsupportedType
        }
    }

    // MARK: - BIP32 Parsing

    static func parseExtendedPublicKey(_ xpub: String) throws -> ExtendedPublicKey {
        // Raw Base58 decode → 82 bytes (78 payload + 4 checksum)
        // Do NOT use Base58Check.decode here — it strips the version byte,
        // but we need all 78 payload bytes (version is part of the BIP32 structure).
        let raw = try Base58.decode(xpub)
        guard raw.count == 82 else { throw DerivationError.invalidKeyLength }

        let payload  = raw.dropLast(4)
        let checksum = raw.suffix(4)
        let computed = doubleSHA256(Data(payload)).prefix(4)
        guard Data(computed) == Data(checksum) else { throw DerivationError.invalidChecksum }

        let decoded = Data(payload) // 78 bytes: version(4) depth(1) fpr(4) idx(4) chain(32) key(33)

        // Use explicit Data copies — NOT slices — so downstream code always
        // sees a zero-based startIndex and a known count.
        let version     = Data(decoded[0..<4])
        let depth       = decoded[4]
        let fingerprint = Data(decoded[5..<9])
        let chainCode   = Data(decoded[13..<45])   // 32 bytes
        let publicKey   = Data(decoded[45..<78])   // 33 bytes

        // Load child index safely without alignment assumptions
        let idxBytes    = [UInt8](decoded[9..<13])
        let childIndex  = UInt32(idxBytes[0]) << 24
                        | UInt32(idxBytes[1]) << 16
                        | UInt32(idxBytes[2]) << 8
                        | UInt32(idxBytes[3])

        return ExtendedPublicKey(
            version: version,
            depth: depth,
            fingerprint: fingerprint,
            childIndex: childIndex,
            chainCode: chainCode,
            publicKey: publicKey
        )
    }

    // MARK: - BIP32 Child Key Derivation (non-hardened only)

    static func deriveChildPublicKey(
        parentKey: Data,
        chainCode: Data,
        index: UInt32
    ) throws -> (key: Data, chainCode: Data) {
        guard index < 0x80000000 else {
            throw DerivationError.derivationFailed("Hardened child keys not supported from xpub")
        }
        // BIP32 requires exactly 33-byte compressed parent key for the HMAC input
        guard parentKey.count == 33 else {
            throw DerivationError.derivationFailed("Parent key must be 33 bytes, got \(parentKey.count)")
        }

        // data = compress(K_parent) || ser32(i)
        // Use explicit Data copy of parentKey to avoid slice-index issues
        var data = Data(parentKey)
        var indexBE = index.bigEndian
        withUnsafeBytes(of: &indexBE) { data.append(contentsOf: $0) }

        // I = HMAC-SHA512(Key = chainCode, Data = data)
        let hmac = HMAC<SHA512>.authenticationCode(
            for: data,
            using: SymmetricKey(data: Data(chainCode))   // explicit copy
        )
        let hmacBytes = [UInt8](hmac)
        let il = Array(hmacBytes[0..<32])    // 32 bytes scalar
        let ir = Data(hmacBytes[32..<64])    // 32 bytes → child chain code

        // child_pubkey = point(IL) + parent_pubkey
        let parentPubKey = try P256K.Signing.PublicKey(
            dataRepresentation: [UInt8](parentKey),
            format: .compressed
        )
        let childPubKey = try parentPubKey.add(il)

        // P256K may return compressed (33 B) or uncompressed (65 B) depending on version.
        // Normalise to compressed 33 bytes so the next derivation step never sees 65 bytes.
        let compressed = try compressedBytes(of: childPubKey)
        return (compressed, ir)
    }

    /// Returns exactly 33 compressed bytes for any P256K signing public key.
    private static func compressedBytes(of key: P256K.Signing.PublicKey) throws -> Data {
        let raw = [UInt8](key.dataRepresentation)
        switch raw.count {
        case 33:
            return Data(raw)
        case 65:
            // 0x04 || X (32 B) || Y (32 B)  →  (0x02 or 0x03) || X
            let prefix: UInt8 = raw[64] % 2 == 0 ? 0x02 : 0x03
            return Data([prefix] + raw[1..<33])
        default:
            throw DerivationError.derivationFailed(
                "Unexpected public key size from P256K: \(raw.count) bytes"
            )
        }
    }

    // MARK: - Hash Utilities

    /// SHA256(SHA256(data))
    static func doubleSHA256(_ data: Data) -> Data {
        let first = SHA256.hash(data: data)
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }

    /// RIPEMD160(SHA256(data))
    static func hash160(_ data: Data) -> Data {
        let sha256 = Data(SHA256.hash(data: data))
        return RIPEMD160.hash(sha256)
    }
}

// MARK: - Base58 / Base58Check

enum Base58 {
    static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    static let alphabetMap: [Character: Int] = {
        var map = [Character: Int]()
        for (i, c) in alphabet.enumerated() { map[c] = i }
        return map
    }()

    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var leadingZeros = 0
        for b in bytes {
            if b == 0 { leadingZeros += 1 } else { break }
        }
        var result = [Character]()
        var num = [UInt8](bytes)
        while !num.isEmpty && !(num.count == 1 && num[0] == 0) {
            var remainder = 0
            var newNum = [UInt8]()
            for byte in num {
                let cur = remainder * 256 + Int(byte)
                let quotient = cur / 58
                remainder = cur % 58
                if !newNum.isEmpty || quotient != 0 {
                    newNum.append(UInt8(quotient))
                }
            }
            result.append(alphabet[remainder])
            num = newNum
        }
        result.append(contentsOf: Array(repeating: alphabet[0], count: leadingZeros))
        return String(result.reversed())
    }

    static func decode(_ string: String) throws -> Data {
        var leadingZeros = 0
        for c in string {
            if c == alphabet[0] { leadingZeros += 1 } else { break }
        }
        var num = [UInt8]()
        for c in string {
            guard let digit = alphabetMap[c] else {
                throw AddressDeriver.DerivationError.invalidBase58
            }
            var carry = digit
            for i in (0..<num.count).reversed() {
                carry += Int(num[i]) * 58
                num[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                num.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }
        let zeros = [UInt8](repeating: 0, count: leadingZeros)
        return Data(zeros + num)
    }
}

enum Base58Check {
    /// Encode payload with a version prefix byte(s)
    static func encode(payload: Data, version: UInt8) -> String {
        var data = Data([version])
        data.append(payload)
        let checksum = AddressDeriver.doubleSHA256(data).prefix(4)
        data.append(checksum)
        return Base58.encode(data)
    }

    /// Decode a Base58Check string → raw payload (without version/checksum)
    static func decode(_ string: String) throws -> Data {
        let decoded = try Base58.decode(string)
        guard decoded.count >= 5 else { throw AddressDeriver.DerivationError.invalidKeyLength }
        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let computed = AddressDeriver.doubleSHA256(Data(payload)).prefix(4)
        guard Data(computed) == Data(checksum) else {
            throw AddressDeriver.DerivationError.invalidChecksum
        }
        // Return without the version prefix (first byte)
        return Data(payload.dropFirst())
    }
}

// MARK: - Bech32 (SegWit Address Encoding)

enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let charsetMap: [Character: UInt8] = {
        var map = [Character: UInt8]()
        for (i, c) in charset.enumerated() { map[c] = UInt8(i) }
        return map
    }()
    private static let generator: [UInt32] = [
        0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3
    ]

    static func encode(hrp: String, witnessVersion: Int, program: Data) throws -> String {
        var data = [UInt8]([UInt8(witnessVersion)])
        data.append(contentsOf: try convertBits(from: [UInt8](program), fromBits: 8, toBits: 5, pad: true))
        let checksum = createChecksum(hrp: hrp, data: data)
        let combined = data + checksum
        var result = hrp + "1"
        for b in combined { result.append(charset[Int(b)]) }
        return result
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if (top >> i) & 1 == 1 { chk ^= generator[i] }
            }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result = [UInt8]()
        for c in hrp.unicodeScalars { result.append(UInt8(c.value >> 5)) }
        result.append(0)
        for c in hrp.unicodeScalars { result.append(UInt8(c.value & 0x1f)) }
        return result
    }

    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        var values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymod = self.polymod(values) ^ 1
        var checksum = [UInt8](repeating: 0, count: 6)
        for i in 0..<6 { checksum[i] = UInt8((polymod >> (5 * (5 - i))) & 0x1f) }
        return checksum
    }

    private static func convertBits(from data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) throws -> [UInt8] {
        var acc = 0
        var bits = 0
        var result = [UInt8]()
        let maxv = (1 << toBits) - 1
        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 { result.append(UInt8((acc << (toBits - bits)) & maxv)) }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            throw AddressDeriver.DerivationError.derivationFailed("Bech32 bit conversion error")
        }
        return result
    }
}

// MARK: - RIPEMD-160 (Pure Swift)

struct RIPEMD160 {

    static func hash(_ data: Data) -> Data {
        var state: (UInt32, UInt32, UInt32, UInt32, UInt32) = (
            0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
        )
        let padded = pad(data)
        for i in stride(from: 0, to: padded.count, by: 64) {
            compress(block: [UInt8](padded[i..<i+64]), state: &state)
        }
        var out = Data(count: 20)
        out.withUnsafeMutableBytes { ptr in
            let p = ptr.bindMemory(to: UInt32.self)
            p[0] = state.0.littleEndian
            p[1] = state.1.littleEndian
            p[2] = state.2.littleEndian
            p[3] = state.3.littleEndian
            p[4] = state.4.littleEndian
        }
        return out
    }

    // MARK: - Private

    private static func pad(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        let bitLen = Int64(data.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0x00) }
        for i in 0..<8 { bytes.append(UInt8((bitLen >> (i * 8)) & 0xFF)) }
        return Data(bytes)
    }

    private static func compress(block: [UInt8], state: inout (UInt32, UInt32, UInt32, UInt32, UInt32)) {
        var X = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            X[i] = UInt32(block[i*4])
                 | (UInt32(block[i*4+1]) << 8)
                 | (UInt32(block[i*4+2]) << 16)
                 | (UInt32(block[i*4+3]) << 24)
        }

        var (al, bl, cl, dl, el) = state
        var (ar, br, cr, dr, er) = state

        // Left pipeline
        for i in 0..<16 {
            let t = rol(al &+ f1(bl, cl, dl) &+ X[rl[i]] &+ kl[0], s: sl[i]) &+ el
            (al, bl, cl, dl, el) = (el, t, bl, rol(cl, s: 10), dl)
        }
        for i in 16..<32 {
            let t = rol(al &+ f2(bl, cl, dl) &+ X[rl[i]] &+ kl[1], s: sl[i]) &+ el
            (al, bl, cl, dl, el) = (el, t, bl, rol(cl, s: 10), dl)
        }
        for i in 32..<48 {
            let t = rol(al &+ f3(bl, cl, dl) &+ X[rl[i]] &+ kl[2], s: sl[i]) &+ el
            (al, bl, cl, dl, el) = (el, t, bl, rol(cl, s: 10), dl)
        }
        for i in 48..<64 {
            let t = rol(al &+ f4(bl, cl, dl) &+ X[rl[i]] &+ kl[3], s: sl[i]) &+ el
            (al, bl, cl, dl, el) = (el, t, bl, rol(cl, s: 10), dl)
        }
        for i in 64..<80 {
            let t = rol(al &+ f5(bl, cl, dl) &+ X[rl[i]] &+ kl[4], s: sl[i]) &+ el
            (al, bl, cl, dl, el) = (el, t, bl, rol(cl, s: 10), dl)
        }

        // Right pipeline
        for i in 0..<16 {
            let t = rol(ar &+ f5(br, cr, dr) &+ X[rr[i]] &+ kr[0], s: sr[i]) &+ er
            (ar, br, cr, dr, er) = (er, t, br, rol(cr, s: 10), dr)
        }
        for i in 16..<32 {
            let t = rol(ar &+ f4(br, cr, dr) &+ X[rr[i]] &+ kr[1], s: sr[i]) &+ er
            (ar, br, cr, dr, er) = (er, t, br, rol(cr, s: 10), dr)
        }
        for i in 32..<48 {
            let t = rol(ar &+ f3(br, cr, dr) &+ X[rr[i]] &+ kr[2], s: sr[i]) &+ er
            (ar, br, cr, dr, er) = (er, t, br, rol(cr, s: 10), dr)
        }
        for i in 48..<64 {
            let t = rol(ar &+ f2(br, cr, dr) &+ X[rr[i]] &+ kr[3], s: sr[i]) &+ er
            (ar, br, cr, dr, er) = (er, t, br, rol(cr, s: 10), dr)
        }
        for i in 64..<80 {
            let t = rol(ar &+ f1(br, cr, dr) &+ X[rr[i]] &+ kr[4], s: sr[i]) &+ er
            (ar, br, cr, dr, er) = (er, t, br, rol(cr, s: 10), dr)
        }

        // Combine
        let T = state.1 &+ cl &+ dr
        state.1 = state.2 &+ dl &+ er
        state.2 = state.3 &+ el &+ ar
        state.3 = state.4 &+ al &+ br
        state.4 = state.0 &+ bl &+ cr
        state.0 = T
    }

    // Round functions
    private static func f1(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ y ^ z }
    private static func f2(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (~x & z) }
    private static func f3(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x | ~y) ^ z }
    private static func f4(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & z) | (y & ~z) }
    private static func f5(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ (y | ~z) }
    private static func rol(_ x: UInt32, s: Int) -> UInt32 { (x << s) | (x >> (32 - s)) }

    // Round constants
    private static let kl: [UInt32] = [0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E]
    private static let kr: [UInt32] = [0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000]

    // Message selection (left pipeline)
    private static let rl: [Int] = [
         0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
         7,  4, 13,  1, 10,  6, 15,  3, 12,  0,  9,  5,  2, 14, 11,  8,
         3, 10, 14,  4,  9, 15,  8,  1,  2,  7,  0,  6, 13, 11,  5, 12,
         1,  9, 11, 10,  0,  8, 12,  4, 13,  3,  7, 15, 14,  5,  6,  2,
         4,  0,  5,  9,  7, 12,  2, 10, 14,  1,  3,  8, 11,  6, 15, 13
    ]

    // Message selection (right pipeline)
    private static let rr: [Int] = [
         5, 14,  7,  0,  9,  2, 11,  4, 13,  6, 15,  8,  1, 10,  3, 12,
         6, 11,  3,  7,  0, 13,  5, 10, 14, 15,  8, 12,  4,  9,  1,  2,
        15,  5,  1,  3,  7, 14,  6,  9, 11,  8, 12,  2, 10,  0,  4, 13,
         8,  6,  4,  1,  3, 11, 15,  0,  5, 12,  2, 13,  9,  7, 10, 14,
        12, 15, 10,  4,  1,  5,  8,  7,  6,  2, 13, 14,  0,  3,  9, 11
    ]

    // Shift amounts (left)
    private static let sl: [Int] = [
        11, 14, 15, 12,  5,  8,  7,  9, 11, 13, 14, 15,  6,  7,  9,  8,
         7,  6,  8, 13, 11,  9,  7, 15,  7, 12, 15,  9, 11,  7, 13, 12,
        11, 13,  6,  7, 14,  9, 13, 15, 14,  8, 13,  6,  5, 12,  7,  5,
        11, 12, 14, 15, 14, 15,  9,  8,  9, 14,  5,  6,  8,  6,  5, 12,
         9, 15,  5, 11,  6,  8, 13, 12,  5, 12, 13, 14, 11,  8,  5,  6
    ]

    // Shift amounts (right)
    private static let sr: [Int] = [
         8,  9,  9, 11, 13, 15, 15,  5,  7,  7,  8, 11, 14, 14, 12,  6,
         9, 13, 15,  7, 12,  8,  9, 11,  7,  7, 12,  7,  6, 15, 13, 11,
         9,  7, 15, 11,  8,  6,  6, 14, 12, 13,  5, 14, 13, 13,  7,  5,
        15,  5,  8, 11, 14, 14,  6, 14,  6,  9, 12,  9, 12,  5, 15,  8,
         8,  5, 12,  9, 12,  5, 14,  6,  8, 13,  6,  5, 15, 13, 11, 11
    ]
}

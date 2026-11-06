import CommonCrypto
import Foundation

/// Electron's `safeStorage` on macOS, which is Chromium's OSCrypt (`os_crypt_mac.mm`): a key
/// derived from the password of the Keychain item "<App> Safe Storage" with PBKDF2-HMAC-SHA1
/// (salt "saltysalt", 1003 rounds, 16 bytes), AES-128-CBC with PKCS#7 and an IV of 16 spaces, the
/// ciphertext prefixed with "v10". QuartzControl stores standard base64 of that output, without a
/// prefix of its own (`connectionsService.ts` `encrypt`).
///
/// QuartzHub only decrypts, for taking secrets over; its own secrets go into Keychain items
/// (docs/formats.md, "Geheimnisse"). `encrypt` exists for the tests.
public enum ChromiumSafeStorage {
  public enum Failure: Error, Equatable {
    case notBase64
    /// Not "v10": another platform (Linux writes "v11") or not safeStorage at all.
    case unknownPrefix
    /// Wrong key or damaged bytes: the padding did not check out.
    case undecryptable
    case notUTF8
  }

  static let prefix = Data("v10".utf8)
  static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

  public static func key(password: String) -> Data {
    var key = Data(count: kCCKeySizeAES128)
    let salt = Data("saltysalt".utf8)
    let passwordBytes = Array(password.utf8)
    let status = key.withUnsafeMutableBytes { keyBuffer in
      salt.withUnsafeBytes { saltBuffer in
        CCKeyDerivationPBKDF(
          CCPBKDFAlgorithm(kCCPBKDF2),
          passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
          saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
          keyBuffer.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128)
      }
    }
    precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
    return key
  }

  /// Decrypts one stored value (the base64 string from connections.json or relay-secrets.json).
  public static func decrypt(base64: String, key: Data) throws(Failure) -> String {
    guard let data = Data(base64Encoded: base64) else { throw .notBase64 }
    guard data.starts(with: prefix) else { throw .unknownPrefix }
    let padded = try crypt(CCOperation(kCCDecrypt), data.dropFirst(prefix.count), key: key, padding: false)
    // PKCS#7 checked here in full: CommonCrypto's own check let a wrong key through (measured:
    // "x" sealed with one key, opened with another, came back as bytes instead of an error).
    // Even a full check passes about one wrong key in 256; the UTF-8 test below catches most of
    // the rest, and the takeover says which secrets it could not read.
    guard let count = padded.last.map(Int.init), (1...kCCBlockSizeAES128).contains(count), padded.count >= count,
          padded.suffix(count).allSatisfy({ Int($0) == count })
    else { throw .undecryptable }
    let plain = padded.dropLast(count)
    guard let text = String(data: plain, encoding: .utf8) else { throw .notUTF8 }
    return text
  }

  public static func encrypt(_ text: String, key: Data) -> String {
    // Encrypting cannot fail on a valid key; the force is for the tests' sake only.
    (prefix + (try! crypt(CCOperation(kCCEncrypt), Data(text.utf8), key: key, padding: true))).base64EncodedString()
  }

  private static func crypt(_ operation: CCOperation, _ input: Data, key: Data, padding: Bool) throws(Failure) -> Data {
    guard padding || (input.count > 0 && input.count % kCCBlockSizeAES128 == 0) else { throw .undecryptable }
    var output = Data(count: input.count + kCCBlockSizeAES128)
    var moved = 0
    let outputCount = output.count
    let status = output.withUnsafeMutableBytes { out in
      input.withUnsafeBytes { inBuffer in
        key.withUnsafeBytes { keyBuffer in
          iv.withUnsafeBytes { ivBuffer in
            CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(padding ? kCCOptionPKCS7Padding : 0),
                    keyBuffer.baseAddress, key.count, ivBuffer.baseAddress,
                    inBuffer.baseAddress, input.count, out.baseAddress, outputCount, &moved)
          }
        }
      }
    }
    guard status == kCCSuccess else { throw .undecryptable }
    return output.prefix(moved)
  }
}

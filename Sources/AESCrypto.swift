import Foundation
import CommonCrypto

/// 华米传输加密：AES-128-CBC + PKCS7，固定 key/iv（与 MiFit 客户端一致）
enum AESCrypto {
    static let hmKey = Data("xeNtBVqzDc6tuNTh".utf8)   // 16 bytes
    static let hmIV  = Data("MAAAYAAAAAAAAABg".utf8)   // 16 bytes

    static func encryptCBC(_ plain: Data) -> Data? {
        let key = hmKey, iv = hmIV
        let outLen = plain.count + kCCBlockSizeAES128
        var out = Data(count: outLen)
        var numBytes: size_t = 0
        let status = out.withUnsafeMutableBytes { outBuf -> CCCryptorStatus in
            plain.withUnsafeBytes { pBuf -> CCCryptorStatus in
                key.withUnsafeBytes { kBuf -> CCCryptorStatus in
                    iv.withUnsafeBytes { iBuf -> CCCryptorStatus in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                kBuf.baseAddress, key.count,
                                iBuf.baseAddress,
                                pBuf.baseAddress, plain.count,
                                outBuf.baseAddress, outLen,
                                &numBytes)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(numBytes)
    }
}

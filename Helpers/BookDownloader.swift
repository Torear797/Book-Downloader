//
//  BookDownloader.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import CommonCrypto
import Foundation

protocol BookDownloader {
    func download() throws
    func deleteDownloaded() throws
    func makeEPUB() throws -> URL
    func deleteCSS() throws
}

struct DefaultBookDownloader: BookDownloader {
    let bookid: String
    let downloader: Downloader
    let secret: String
    let provider: Provider
    
    init(bookid: String, downloader: Downloader, secret: String? = nil, provider: Provider) throws {
        self.bookid = bookid
        self.downloader = downloader
        self.provider = provider
        
        if let secret {
            self.secret = secret
        } else {
            self.secret = try Self.downloadSecret(downloader: downloader, provider: provider)
        }
    }

    func download() throws {
        let encryptedMetadata = try downloadMetadata(bookid)
        let metadata = try decryptMetadata(encryptedMetadata, secret: secret)
        
        try processMetadata(metadata)
    }
    
    func deleteDownloaded() throws {
        try downloader.deleteDownloaded()
    }
    
    func makeEPUB() throws -> URL {
        try downloader.makeEPUB()
    }
    
    func deleteCSS() throws {
        try downloader.deleteCSS()
    }
}

extension DefaultBookDownloader {
    private static func downloadSecret(downloader: Downloader, provider: Provider) throws -> String {
        let url = "https://\(provider.domain)/reader/p/api/v5/metadata_secret?lang=ru"
        let data = try downloader.requestURL(url)
        
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let secret = json["secret"] as? String
        else {
            throw NSError(
                domain: "JSONError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse secret response"]
            )
        }
        
        print("Secret: \(secret)")
        
        return secret
    }
    
    private func downloadMetadata(_ bookid: String) throws -> [String: Any] {
        let url = "https://\(provider.domain)/p/api/v5/books/\(bookid)/metadata/v4"
        let data = try downloader.requestURL(url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "JSONError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse metadata response"]
            )
        }
        
        return json
    }
    
    private func decryptMetadata(_ encryptedMetadata: [String: Any], secret: String) throws -> [String: Any] {
        var metadata: [String: Any] = [:]
        
        for (key, value) in encryptedMetadata {
            if let array = value as? [UInt8] {
                let data = Data(array)
                let decryptedData = try decrypt(secret, data: data)
                
                metadata[key] = decryptedData
                
            } else {
                metadata[key] = value
            }
        }
        
        return metadata
    }

    private func decrypt(_ secret: String, data: Data) throws -> Data {
        guard let keyData = Data(base64Encoded: secret) else {
            throw NSError(
                domain: "CryptoError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode secret"]
            )
        }
        
        let iv = data.prefix(16)
        let cryptData = data.suffix(from: 16)
        let decryptedData = try aesCBCDecrypt(cryptData, key: keyData, iv: iv)
        let padSize = -Int(decryptedData.last ?? 0)
        
        return decryptedData.prefix(decryptedData.count + padSize)
    }
    
    private func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        var decryptedData = Data(count: data.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = .zero
        
        let cryptStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    
                    var localDecryptedData = decryptedData
                    
                    let status = localDecryptedData.withUnsafeMutableBytes { decryptedBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            decryptedBytes.baseAddress, decryptedData.count,
                            &numBytesDecrypted
                        )
                    }
                    decryptedData = localDecryptedData
                    return status
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else {
            throw NSError(domain: "CryptoError", code: Int(cryptStatus), userInfo: [NSLocalizedDescriptionKey: "AES decryption failed"])
        }
        
        return decryptedData.prefix(numBytesDecrypted)
    }
    
    private func processMetadata(_ metadata: [String: Any]) throws {
        guard let containerData = metadata["container"] as? Data,
              let opfData = metadata["opf"] as? Data,
              let ncxData = metadata["ncx"] as? Data,
              let documentUUID = metadata["document_uuid"] as? String else {
            
            throw NSError(
                domain: "MetadataError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing required metadata fields"]
            )
        }
        
        try downloader.saveBytes(Data("application/epub+zip".utf8), name: "mimetype")
        try downloader.saveBytes(containerData, name: "META-INF/container.xml")
        try downloader.saveBytes(opfData, name: "OEBPS/content.opf")
        try processOPF(documentUUID)
        try downloader.saveBytes(ncxData, name: "OEBPS/toc.ncx")
    }
    
    private func processOPF(_ uuid: String) throws {
        let contentFile = downloader.outdir.appendingPathComponent("OEBPS/content.opf")
        let contentData = try Data(contentsOf: contentFile)
        
        guard let xmlString = String(data: contentData, encoding: .utf8) else {
            throw NSError(
                domain: "XMLError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode XML"]
            )
        }
        
        let pattern = "<item\\s+[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>"
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let matches = regex.matches(
            in: xmlString,
            options: [],
            range: NSRange(location: 0, length: xmlString.utf16.count)
        )
        
        for match in matches {
            if match.numberOfRanges > 1 {
                let hrefRange = match.range(at: 1)
                if let range = Range(hrefRange, in: xmlString) {
                    let href = String(xmlString[range])
                    
                    if href != "toc.ncx" {
                        print("Found item with href: \(href)")
                        
                        let url = "https://\(provider.domain)/p/a/4/d/\(uuid)/contents/OEBPS/\(href)"
                        
                        do {
                            let data = try downloader.requestURL(url)
                            
                            try downloader.saveBytes(data, name: "OEBPS/\(href)")
                            
                            print("Successfully downloaded: \(href)")
                        } catch {
                            print("Warning: Cannot download from '\(url)': \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

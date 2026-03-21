//
//  DefaultBookDownloader.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import CommonCrypto
import Foundation

protocol IBookDownloader {
    func download() async throws
    func deleteDownloaded() throws
    func makeEPUB() throws -> URL
    func deleteCSS() throws
}

struct DefaultBookDownloader: IBookDownloader {
    let bookid: String
    let downloader: Downloader
    let secret: String
    let provider: Provider
    
    init(bookid: String, downloader: Downloader, secret: String, provider: Provider) throws {
        self.bookid = bookid
        self.downloader = downloader
        self.provider = provider
        self.secret = secret
    }
    
    func download() async throws {
        let encryptedMetadata = try await downloadMetadata(bookid)
        let metadata = try decryptMetadata(encryptedMetadata, secret: secret)
        
        try await processMetadata(metadata)
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
    private func downloadMetadata(_ bookid: String) async throws -> [String: Any] {
        let url = "https://\(provider.domain)/p/api/v5/books/\(bookid)/metadata/v4"
        let data = try await downloader.requestURL(url)
        
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
    
    private func processMetadata(_ metadata: [String: Any]) async throws {
        guard let containerData = metadata["container"] as? Data,
              let opfData = metadata["opf"] as? Data,
              let ncxData = metadata["ncx"] as? Data,
              let cover = makeCover(),
              let documentUUID = metadata["document_uuid"] as? String else {
            
            throw NSError(
                domain: "MetadataError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing required metadata fields"]
            )
        }
        
        try downloader.saveBytes(Data("application/epub+zip".utf8), name: "mimetype")
        
        try downloader.saveBytes(clearTrash(containerData, trash: .meta), name: "META-INF/container.xml")
        try downloader.saveBytes(cover, name: "OEBPS/cover.xhtml")
        try downloader.saveBytes(clearTrash(opfData, trash: .content), name: "OEBPS/content.opf")
        try await processOPF(documentUUID)
        try downloader.saveBytes(clearTrash(ncxData, trash: .toc), name: "OEBPS/toc.ncx")
    }
    
    private func clearTrash(_ data: Data, trash: TrashProvider) -> Data {
        guard let trashString: String = String(data: data, encoding: .utf8) else {
            return data
        }
        
        var clearString: String = trashString
        
        switch trash {
        case .meta:
            clearString = clearString.replacingOccurrences(of: "</c", with: "</container>")
        case .content:
            if trashString.last == "<" {
                clearString.append("/package>")
            } else {
                clearString = trashString
            }
            clearString = fixContentOf(clearString)
        case .toc:
            clearString.append("p>")
            clearString.append("</ncx>")
        }
        
        return clearString.data(using: .utf8) ?? data
    }
    
    private func processOPF(_ uuid: String) async throws {
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
                            let data = try await downloader.requestURL(url)
                            let fixedData: Data
                            
                            if let stringData = String(data: data, encoding: .utf8) {
                                let fixedString = fixHTML(stringData)
                                fixedData = fixedString.data(using: .utf8) ?? data
                            } else {
                                fixedData = data
                            }
                            
                            try downloader.saveBytes(fixedData, name: "OEBPS/\(href)")
                            
                            print("Successfully downloaded: \(href)")
                        } catch {
                            print("Warning: Cannot download from '\(url)': \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    private func fixHTML(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<(link|meta|img|br)([^>]*)>") else {
            return html
        }
        
        let range = NSRange(location: 0, length: html.utf16.count)
        
        var result: String = regex.stringByReplacingMatches(
            in: html,
            range: range,
            withTemplate: "<$1$2 />"
        )
        
        let newDocType = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
        """
        
        result = result.replacingOccurrences(
            of: "<!DOCTYPE html>",
            with: newDocType
        )
        
        let newHTML = """
        <html xmlns="http://www.w3.org/1999/xhtml">
        """
        result = result.replacingOccurrences(of: "<html>", with: newHTML)
        
        return result
    }
    
    private func fixContentOf(_ content: String) -> String {
        var result: String = content
        
        let pattern = "<item id=\"(?!ncxtoc\"|cover_image|css1\")([^\"]*)\" href"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: result.utf16.count)
        
        result = regex?.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: "<item id =\"id_$1\" href"
        ) ?? result
        
        let patternRef = "<itemref idref=\"([^>]*)/>"
        let regexRef = try? NSRegularExpression(pattern: patternRef)
        let rangeRef = NSRange(location: 0, length: result.utf16.count)
        
        result = regexRef?.stringByReplacingMatches(
            in: result,
            range: rangeRef,
            withTemplate: "<itemref idref=\"id_$1/>"
        ) ?? result
        
        let coverPattern = """
        <item id="cover_image" href="cover.jpg" media-type="image/jpeg"/>
        """
        
        let newCoverPattern = """
        <item id="cover_image" href="cover.jpg" media-type="image/jpeg"/>\n
        <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
        """
        
        result = result.replacingOccurrences(of: coverPattern, with: newCoverPattern)
        
        
        let coverRefPattern = """
        <reference href="cover.jpg" type="cover" title="Cover"/>
        """
        
        let newCoverRefPattern = """
        <reference href="cover.xhtml" type="cover" title="Cover"/>
        """
        
        result = result.replacingOccurrences(of: coverRefPattern, with: newCoverRefPattern)
        
        return result
    }
    
    private func makeCover() -> Data? {
        let html: String = """
         <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
         <html xmlns="http://www.w3.org/1999/xhtml">
         <head>
            <title>Cover</title>
         </head>
         <body>
            <div style="text-align: center; padding: 0; margin: 0;">
                <img src="cover.jpg" alt="Cover Image" style="height: 100%; max-width: 100%;"/>
            </div>
         </body>
         </html>
        """
        
        return html.data(using: .utf8)
    }
}

extension DefaultBookDownloader {
    enum TrashProvider {
        case meta
        case content
        case toc
    }
}

//
//  Downloader.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import Foundation
import ZIPFoundation

struct Downloader {
    let outdir: URL
    let cookies: [HTTPCookie]
    
    init(outdir: URL, cookies: [HTTPCookie]) {
        self.outdir = outdir
        self.cookies = cookies
    }
    
    func saveBytes(_ data: Data, name: String) throws {
        let fileURL = outdir.appendingPathComponent(name)
        let directoryURL = fileURL.deletingLastPathComponent()
        
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }
    
    func requestURL(_ urlString: String) async throws -> Data {
        print("Downloading \(urlString)...")
        
        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "InvalidURL",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"]
            )
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        request.allHTTPHeaderFields = cookieHeader
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Invalid Response", code: -1)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(
                domain: "HTTPError",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP Status: \(httpResponse.statusCode)"]
            )
        }

        return data
    }
    
    func deleteDownloaded() throws {
        try FileManager.default.removeItem(at: outdir)
    }
    
    func deleteCSS() throws {
        let enumerator = FileManager.default.enumerator(at: outdir, includingPropertiesForKeys: nil)
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "css" {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    func makeEPUB() throws -> URL {
        let epubURL = outdir.appendingPathExtension("epub")
        let archive = try Archive(url: epubURL, accessMode: .create)
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: outdir, includingPropertiesForKeys: nil)
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let relativePath = fileURL.relativePath.replacingOccurrences(of: outdir.path + "/", with: "")
            
            if relativePath == "mimetype" {
                try archive.addEntry(with: relativePath, fileURL: fileURL, compressionMethod: .none)
            } else {
                try archive.addEntry(with: relativePath, fileURL: fileURL, compressionMethod: .deflate)
            }
        }
        
        return epubURL
    }
}

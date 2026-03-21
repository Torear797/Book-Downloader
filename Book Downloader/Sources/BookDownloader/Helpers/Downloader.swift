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
        
        try ensureEPUBStructure()
        
        let archive = try Archive(url: epubURL, accessMode: .create)
        let fileManager = FileManager.default
        let filesToAdd = [
            outdir.appendingPathComponent("mimetype"),
            outdir.appendingPathComponent("META-INF/container.xml"),
            outdir.appendingPathComponent("OEBPS/content.opf"),
            outdir.appendingPathComponent("OEBPS/toc.ncx")
        ]
        
        for fileURL in filesToAdd {
            if fileManager.fileExists(atPath: fileURL.path) {
                let relativePath = fileURL.relativePath.replacingOccurrences(of: outdir.path + "/", with: "")
                if relativePath == "mimetype" {
                    try archive.addEntry(with: relativePath, fileURL: fileURL, compressionMethod: .none)
                } else {
                    try archive.addEntry(with: relativePath, fileURL: fileURL, compressionMethod: .deflate)
                }
            }
        }
        
        let oebpsURL = outdir.appendingPathComponent("OEBPS")
        
        if fileManager.fileExists(atPath: oebpsURL.path) {
            let enumerator = fileManager.enumerator(
                at: oebpsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            
            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true { continue }
                
                if fileURL.lastPathComponent != "content.opf" && fileURL.lastPathComponent != "toc.ncx" {
                    let relativePath = fileURL.relativePath.replacingOccurrences(of: outdir.path + "/", with: "")
                    try archive.addEntry(with: relativePath, fileURL: fileURL, compressionMethod: .deflate)
                }
            }
        }
        
        return epubURL
    }
    
    private func ensureEPUBStructure() throws {
        try FileManager.default.createDirectory(
            at: outdir.appendingPathComponent("META-INF"),
            withIntermediateDirectories: true
        )
        
        try FileManager.default.createDirectory(
            at: outdir.appendingPathComponent("OEBPS"),
            withIntermediateDirectories: true
        )
        
        let mimetypeURL = outdir.appendingPathComponent("mimetype")
        
        if !FileManager.default.fileExists(atPath: mimetypeURL.path) {
            try "application/epub+zip".write(to: mimetypeURL, atomically: true, encoding: .ascii)
        }
        
        let containerURL = outdir.appendingPathComponent("META-INF/container.xml")
        
        if !FileManager.default.fileExists(atPath: containerURL.path) {
            let containerContent = """
           <?xml version="1.0" encoding="UTF-8"?>
           <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
               <rootfiles>
                   <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
               </rootfiles>
           </container>
           """
            try containerContent.write(to: containerURL, atomically: true, encoding: .utf8)
        }
    }
}

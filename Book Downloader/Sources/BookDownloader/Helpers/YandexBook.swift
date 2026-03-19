//
//  YandexBook.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import Foundation

struct YandexBook {
    let outdir: URL
    let cookies: [HTTPCookie]
    
    init(outdir: URL, cookies: [HTTPCookie]) throws {
        if !FileManager.default.fileExists(atPath: outdir.path) {
            try FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)
        }
        
        self.outdir = outdir
        self.cookies = cookies
    }
    
    func getBook(bookid: String) async throws -> IBookDownloader {
        let bookOutdir = outdir.appendingPathComponent(bookid)
        let downloader = Downloader(outdir: bookOutdir, cookies: cookies)
        let secret = try await downloadSecret(downloader: downloader, provider: .yandexBooks)
        
        return try DefaultBookDownloader(
            bookid: bookid,
            downloader: downloader,
            secret: secret,
            provider: .yandexBooks
        )
    }
    
    private func downloadSecret(downloader: Downloader, provider: Provider) async throws -> String {
        let url = "https://\(provider.domain)/reader/p/api/v5/metadata_secret?lang=ru"
        let data = try await downloader.requestURL(url)
        
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
}

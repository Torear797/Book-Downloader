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
    
    func getBook(bookid: String) throws -> BookDownloader {
        let bookOutdir = outdir.appendingPathComponent(bookid)
        let downloader = Downloader(outdir: bookOutdir, cookies: cookies)
        
        return try DefaultBookDownloader(bookid: bookid, downloader: downloader, provider: .yandexBooks)
    }
}

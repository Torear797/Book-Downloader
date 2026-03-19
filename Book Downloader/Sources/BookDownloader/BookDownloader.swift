// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

@main
struct BookDownloader {
    static func main() async {
        print("Welcome to the Book Downloader!")
        print("created by torear \n")
        
        let arguments: [String] = CommandLine.arguments
        let argumentChecker: ArgumentChecker = DefaultArgumentChecker()
        let argumentParser: ArgumentParser = DefaultArgumentParser(argumentChecker: argumentChecker)
        let cookieBuilder: CookieBuilder = DefaultCookieBuilder(provider: .yandexBooks)
        
        do {
            let result = try argumentParser.parse(arguments: arguments)
            let cookies = try cookieBuilder.getCookies()
            let yandexBook = try YandexBook(outdir: result.outputPath, cookies: cookies)
            let book = try await yandexBook.getBook(bookid: result.bookID)
            
            try await book.download()
            try book.deleteCSS()
            let epubBook = try book.makeEPUB()
            try book.deleteDownloaded()
            
            print("Successfully created EPUB at: \(epubBook.path(percentEncoded: true))")
        } catch {
            print("Error \(error.localizedDescription)")
            return
        }
    }
}

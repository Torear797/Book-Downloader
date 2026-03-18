//
//  ArgumentParser.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import Foundation

enum Argument: String {
    case bookID = "--bookid"
    case outputPath = "--outdir"
}

enum ArgumentParserError: Error {
    case invalidArguments
    case invalidBookID
}

protocol ArgumentParser {
    func parse(arguments: [String]) throws -> (bookID: String, outputPath: URL)
}

struct DefaultArgumentParser: ArgumentParser {
    let argumentChecker: ArgumentChecker
    
    func parse(arguments: [String]) throws -> (bookID: String, outputPath: URL) {
        do {
            try argumentChecker.check(arguments: arguments)
        } catch {
            throw ArgumentParserError.invalidArguments
        }
        
        var bookID: String?
        var outputPath: URL = URL(filePath: "out")
        
        for i in 1..<arguments.count {
            let argument = arguments[i]
            
            switch argument {
            case Argument.bookID.rawValue:
                bookID = arguments[i + 1]
            case Argument.outputPath.rawValue:
                outputPath = URL(filePath: arguments[i + 1])
            default:
                continue
            }
        }
        
        guard let bookID else { throw ArgumentParserError.invalidBookID }
        
        return (bookID: bookID, outputPath: outputPath)
    }
}

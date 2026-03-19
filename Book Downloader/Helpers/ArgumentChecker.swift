//
//  ArgumentChecker.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

enum ArgumentCheckerError: Error {
    case imvalidArguments
}

protocol ArgumentChecker {
    func check(arguments: [String]) throws
}

struct DefaultArgumentChecker: ArgumentChecker {
    func check(arguments: [String]) throws {
        guard arguments.count > 1, arguments.count < 4 else {
            print("Usage: \(arguments[0]) --bookid <bookid> [--outdir <outdir>]")
            throw ArgumentCheckerError.imvalidArguments
        }
    }
}

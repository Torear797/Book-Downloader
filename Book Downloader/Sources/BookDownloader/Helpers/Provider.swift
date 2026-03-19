//
//  Provider.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

enum Provider {
    case yandexBooks
    
    var domain: String {
        switch self {
        case .yandexBooks:
            "books.yandex.ru"
        }
    }
}

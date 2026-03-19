//
//  OPFParserDelegate.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import Foundation

class OPFParserDelegate: NSObject, XMLParserDelegate {
    let uuid: String
    let downloader: Downloader
    let provider: Provider
    var currentElement: String = ""
    
    init(uuid: String, downloader: Downloader, provider: Provider) {
        self.uuid = uuid
        self.downloader = downloader
        self.provider = provider
    }
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        
        if elementName == "item", let href = attributeDict["href"], href != "toc.ncx" {
            print("File: \(href)")
            
            let url = "https://\(provider.domain)/p/a/4/d/\(uuid)/contents/OEBPS/\(href)"
            
            do {
                let data = try downloader.requestURL(url)
                try downloader.saveBytes(data, name: "OEBPS/\(href)")
            } catch {
                print("Warning: Cannot download from '\(url)': \(error.localizedDescription)")
            }
        }
    }
}

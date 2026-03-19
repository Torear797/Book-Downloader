//
//  CookieBuilder.swift
//  Book Downloader
//
//  Created by Артём Клыч on 18.03.2026.
//

import Foundation

protocol CookieBuilder {
    func getCookies() throws -> [HTTPCookie]
}

struct DefaultCookieBuilder: CookieBuilder {
    let provider: Provider
    
    func getCookies() throws -> [HTTPCookie] {
        let authCookieName: String = "Session_id"
        
        if let sessionID = ProcessInfo.processInfo.environment["SESSION_ID"] {
            let cookieProperties: [HTTPCookiePropertyKey: Any] = [
                .name: authCookieName,
                .value: sessionID,
                .domain: provider.domain,
                .path: "/"
            ]
            
            if let cookie = HTTPCookie(properties: cookieProperties) {
                return [cookie]
            }
        }
        
        print("- Enter \(authCookieName) cookie - \n")
        print("(your browser -> developer tools -> application -> Cookies -> https://\(provider.domain) -> \(authCookieName) -> Value):")
        
        guard let sessionID = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty else {
            throw NSError(domain: "CookieError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No session ID provided"])
        }
        
        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: authCookieName,
            .value: sessionID,
            .domain: provider.domain,
            .path: "/"
        ]
        
        guard let cookie = HTTPCookie(properties: cookieProperties) else {
            throw NSError(
                domain: "CookieError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create cookie"]
            )
        }
        
        return [cookie]
    }
}

//
//  CacheManager.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 17-06-2026.
//

import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    private let defaults: UserDefaults?
    private let cacheDuration: TimeInterval = 5 * 60 // 5 minutes
    
    private init() {
        self.defaults = UserDefaults(suiteName: AppConstants.suiteName)
    }
    
    struct CacheEntry<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }
    
    private struct AnyCacheEntry: Codable {
        let timestamp: Date
    }
    
    func getTimestamp(forKey key: String) -> Date? {
        guard let data = defaults?.data(forKey: key),
              let entry = try? JSONDecoder().decode(AnyCacheEntry.self, from: data) else {
            return nil
        }
        return entry.timestamp
    }
    
    /// Removes every entry written by this manager (anything stored as a timestamped `CacheEntry`).
    func clearAll() {
        guard let defaults else { return }
        for (key, value) in defaults.dictionaryRepresentation() {
            if let data = value as? Data, (try? JSONDecoder().decode(AnyCacheEntry.self, from: data)) != nil {
                defaults.removeObject(forKey: key)
            }
        }
    }
    
    func save<T: Codable>(_ data: T, forKey key: String) {
        if AppConstants.isScreenshotMode { return }
        
        let entry = CacheEntry(data: data, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(entry) {
            defaults?.set(encoded, forKey: key)
        }
    }
    
    func load<T: Codable>(forKey key: String, ignoreExpiration: Bool = false) -> T? {
        if AppConstants.isScreenshotMode { return nil }
        
        guard let data = defaults?.data(forKey: key),
              let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else {
            return nil
        }
        
        if !ignoreExpiration {
            let elapsedTime = Date().timeIntervalSince(entry.timestamp)
            if elapsedTime > cacheDuration {
                return nil
            }
        }
        
        return entry.data
    }
}

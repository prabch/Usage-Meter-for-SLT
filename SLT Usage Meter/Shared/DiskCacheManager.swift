//
//  DiskCacheManager.swift
//  SLT Usage Meter
//
//  Created by Usage Meter Team.
//

import Foundation

class DiskCacheManager {
    static let shared = DiskCacheManager()
    
    private let cacheDurationCurrentMonth: TimeInterval = 6 * 60 * 60 // 6 hours
    
    private init() {}
    
    private var sharedCacheDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.suiteName)?
            .appendingPathComponent("Caches")
            .appendingPathComponent("NetworkPayloads")
    }
    
    private func ensureDirectoryExists() {
        guard let url = sharedCacheDirectory else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func fileURL(forKey key: String) -> URL? {
        sharedCacheDirectory?.appendingPathComponent("\(key).json")
    }
    
    struct CacheMetadata: Codable {
        let timestamp: Date
    }
    
    func save<T: Codable>(_ data: T, forKey key: String) {
        ensureDirectoryExists()
        guard let fileURL = fileURL(forKey: key) else { return }
        
        // Wrap data with timestamp to check expiration later
        let wrapper = Wrapper(data: data, timestamp: Date())
        
        do {
            let data = try JSONEncoder().encode(wrapper)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save to DiskCacheManager: \(error)")
        }
    }
    
    func load<T: Codable>(forKey key: String, ignoreExpiration: Bool = false, isCurrentMonth: Bool = false) -> T? {
        guard let fileURL = fileURL(forKey: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let wrapper = try JSONDecoder().decode(Wrapper<T>.self, from: data)
            
            if !ignoreExpiration && isCurrentMonth {
                let elapsedTime = Date().timeIntervalSince(wrapper.timestamp)
                if elapsedTime > cacheDurationCurrentMonth {
                    return nil
                }
            }
            
            return wrapper.data
        } catch {
            print("Failed to load from DiskCacheManager: \(error)")
            return nil
        }
    }
    
    private struct Wrapper<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }
}

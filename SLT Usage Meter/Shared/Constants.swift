//
//  Constants.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2026-01-06.
//

import Foundation

struct AppConstants {
    static let suiteName = "group.com.prabch.sltusage"
    
    struct API {
        static let baseURL = "https://omniscapp.slt.lk/slt/ext/api"
        static let clientId = Secrets.clientId
    }
    
    struct Keys {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let username = "username" // This is the email
        static let cachedAccounts = "cachedAccounts"
        static let wasSignedIn = "wasSignedIn"
    }
    
    #if DEBUG
    static var isScreenshotMode: Bool = {
        let defaults = UserDefaults(suiteName: suiteName)
        if ProcessInfo.processInfo.arguments.contains("-isScreenshotMode") {
            defaults?.set(true, forKey: "ScreenshotModeActive")
            return true
        }
        
        if Bundle.main.bundlePath.hasSuffix(".app") {
            defaults?.set(false, forKey: "ScreenshotModeActive")
            return false
        }
        
        return defaults?.bool(forKey: "ScreenshotModeActive") ?? false
    }()
    #else
    static var isScreenshotMode: Bool { false }
    #endif
}

enum APIEndpoint {
    case login
    case accountDetail(username: String)
    case usageSummary(subscriberID: String)
    case vasBundles(subscriberID: String)
    case refreshToken
    
    var url: URL {
        switch self {
        case .login:
            return URL(string: "\(AppConstants.API.baseURL)/Account/Login")!
        case .accountDetail(let username):
            return URL(string: "\(AppConstants.API.baseURL)/AccountOMNI/GetAccountDetailRequest?username=\(username)")!
        case .usageSummary(let subscriberID):
            return URL(string: "\(AppConstants.API.baseURL)/BBVAS/UsageSummary?subscriberID=\(subscriberID)")!
        case .vasBundles(let subscriberID):
            return URL(string: "\(AppConstants.API.baseURL)/BBVAS/GetDashboardVASBundles?subscriberID=\(subscriberID)")!
        case .refreshToken:
            return URL(string: "\(AppConstants.API.baseURL)/Account/RefreshToken")!
        }
    }
}

import Security

// MARK: - Auth Diagnostics

/// Persistent, token-free log of auth events shared by the app and widget (App Group container).
/// Used to find out *why* a session ended. Never log token values.
enum AuthLog {
    private static let maxBytes = 48 * 1024
    private static let queue = DispatchQueue(label: "com.prabch.sltusage.authlog")
    
    static var processTag: String {
        Bundle.main.bundlePath.hasSuffix(".appex") ? "widget" : "app"
    }
    
    static var isExtension: Bool { processTag == "widget" }
    
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.suiteName)?
            .appendingPathComponent("auth.log")
    }
    
    static func log(_ message: String) {
        print("AuthLog[\(processTag)]: \(message)")
        queue.sync {
            guard let url = fileURL else { return }
            let stamp = ISO8601DateFormatter().string(from: Date())
            guard let data = "\(stamp) [\(processTag)] \(message)\n".data(using: .utf8) else { return }
            
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > maxBytes,
               let existing = try? Data(contentsOf: url) {
                try? existing.suffix(maxBytes / 2).write(to: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
    }
    
    static func read() -> String {
        guard let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return "(no auth events recorded)"
        }
        return text
    }
}

/// Advisory file lock in the App Group container so the app and the widget extension never
/// refresh a (possibly single-use, rotating) refresh token at the same time.
enum CrossProcessLock {
    static func withLock<T>(timeout: TimeInterval = 20, _ body: () async throws -> T) async throws -> T {
        var fd: Int32 = -1
        if let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.suiteName)?
            .appendingPathComponent("refresh.lock") {
            fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        }
        
        var locked = false
        if fd >= 0 {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                if flock(fd, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
                if Date() > deadline { break }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            if !locked { AuthLog.log("refresh lock timeout after \(Int(timeout))s; proceeding without lock") }
        }
        defer {
            if fd >= 0 {
                if locked { flock(fd, LOCK_UN) }
                close(fd)
            }
        }
        return try await body()
    }
}

struct KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    private let serviceName = "SLT Usage Meter"
    
    /// Atomic local-only upsert (shared via App Group keychain-access-groups, NOT iCloud-synced).
    /// Keeping tokens local prevents an older/other device on the same Apple ID from wiping or
    /// racing rotating refresh tokens via iCloud Keychain.
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        var status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key,
                kSecAttrLabel as String: "SLT \(key.capitalized)",
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: kCFBooleanFalse!
            ]
            status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecDuplicateItem { // lost a race with the other process
                status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
            }
        }
        if status != errSecSuccess {
            AuthLog.log("keychain save FAILED key=\(key) status=\(status)")
        }
        return status == errSecSuccess
    }
    
    func read(forKey key: String) -> String? {
        readWithStatus(forKey: key).value
    }
    
    /// Like `read`, but exposes the OSStatus so callers can tell "not stored" from "temporarily unreadable".
    func readWithStatus(forKey key: String) -> (value: String?, status: OSStatus) {
        readWithStatus(forKey: key, synchronizable: kCFBooleanFalse!)
    }
    
    private func readWithStatus(forKey key: String, synchronizable: CFTypeRef) -> (value: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizable
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return (String(data: data, encoding: .utf8), status)
        }
        if status != errSecItemNotFound {
            AuthLog.log("keychain read UNEXPECTED key=\(key) status=\(status)")
        }
        return (nil, status)
    }
    
    /// One-time migration for users upgrading from builds that stored iCloud-synced tokens.
    /// Copies existing synced credentials into local-only storage without deleting the synced copy.
    func migrateFromSyncedKeychainIfNeeded() {
        let defaults = UserDefaults(suiteName: AppConstants.suiteName)
        let migratedKey = "didMigrateLocalKeychain"
        guard defaults?.bool(forKey: migratedKey) != true else { return }
        defer { defaults?.set(true, forKey: migratedKey) }
        
        guard readWithStatus(forKey: AppConstants.Keys.accessToken).value == nil else { return }
        
        let keys = [AppConstants.Keys.accessToken, AppConstants.Keys.refreshToken, AppConstants.Keys.username]
        var copiedAny = false
        for key in keys {
            if let syncedValue = readWithStatus(forKey: key, synchronizable: kCFBooleanTrue!).value {
                save(syncedValue, forKey: key)
                copiedAny = true
            }
        }
        if copiedAny {
            AuthLog.log("migrated credentials from iCloud keychain to local-only keychain")
        }
    }
    
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

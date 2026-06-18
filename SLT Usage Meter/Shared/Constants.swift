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
    }
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

struct KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    private let serviceName = "SLT Usage Meter"
    
    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        // Remove existing item (both local and synchronizable) first to prevent duplicate key errors
        delete(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrLabel as String: "SLT \(key.capitalized)",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanTrue! // Enables iCloud Keychain sync
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny // Search both local and iCloud synced items
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny // Delete from both local and iCloud synced items
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

//
//  NetworkManager.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2026-01-06.
//

import Foundation
import WidgetKit

enum APIError: LocalizedError {
    case decodingFailed(message: String, rawResponse: String)
    
    var errorDescription: String? {
        switch self {
        case .decodingFailed(let message, _):
            return message
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    
    private init() {
        KeychainHelper.shared.migrateFromSyncedKeychainIfNeeded()
    }
    
    // Custom URLSession with extended timeouts to prevent -1005 errors
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60  // 60 seconds
        configuration.timeoutIntervalForResource = 120 // 120 seconds
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        #if DEBUG
        if AppConstants.isScreenshotMode {
            configuration.protocolClasses = [MockDataURLProtocol.self] + (configuration.protocolClasses ?? [])
        }
        #endif

        return URLSession(configuration: configuration)
    }()
    
    // Percent encode strings for application/x-www-form-urlencoded payloads
    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+/=&?@#$*,;")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
    
    // MARK: - Auth Helpers
    
    var accessToken: String? {
        get { KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken) }
    }
    
    var username: String? {
        get { KeychainHelper.shared.read(forKey: AppConstants.Keys.username) }
    }
    
    func logout(reason: String = "unspecified") {
        AuthLog.log("LOGOUT: \(reason). Wiping keychain.")
        UserDefaults(suiteName: AppConstants.suiteName)?.set(false, forKey: AppConstants.Keys.wasSignedIn)
        KeychainHelper.shared.delete(forKey: AppConstants.Keys.accessToken)
        KeychainHelper.shared.delete(forKey: AppConstants.Keys.refreshToken)
        KeychainHelper.shared.delete(forKey: AppConstants.Keys.username)
        
        // Notification for App to show login screen
        NotificationCenter.default.post(name: NSNotification.Name("TokenExpired"), object: nil)
        
        // Reload widgets to show logged out state
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - API Calls
    
    func login(username: String, password: String) async throws -> String {
        let url = APIEndpoint.login.url
        var request = createBaseRequest(url: url, method: "POST", isUrlEncoded: true)
        
        let encodedUsername = percentEncode(username)
        let encodedPassword = percentEncode(password)
        let body = "username=\(encodedUsername)&password=\(encodedPassword)&channelID=WEB"
        request.httpBody = body.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 200 {
            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
            
            // Save credentials securely in Keychain
            KeychainHelper.shared.save(loginResponse.accessToken, forKey: AppConstants.Keys.accessToken)
            if let newRefreshToken = loginResponse.refreshToken {
                KeychainHelper.shared.save(newRefreshToken, forKey: AppConstants.Keys.refreshToken)
            }
            KeychainHelper.shared.save(username, forKey: AppConstants.Keys.username)
            UserDefaults(suiteName: AppConstants.suiteName)?.set(true, forKey: AppConstants.Keys.wasSignedIn)
            AuthLog.log("login OK; refreshToken \(loginResponse.refreshToken == nil ? "NOT returned" : "stored")")
            WidgetCenter.shared.reloadAllTimelines()
            
            return loginResponse.accessToken
        } else {
            throw NSError(domain: "Auth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Login failed with status \(httpResponse.statusCode)"])
        }
    }
    
    func fetchAccounts(forceRefresh: Bool = false) async throws -> [AccountInfo] {
        guard let username = username else { throw URLError(.userAuthenticationRequired) }
        
        let cacheKey = "accounts_\(username)"
        if !forceRefresh, let cached: [AccountInfo] = CacheManager.shared.load(forKey: cacheKey) {
            return cached
        }
        
        let url = APIEndpoint.accountDetail(username: username).url
        
        do {
            let finalRequest = try createRequest(url: url)
            let (data, _) = try await execute(request: finalRequest)
            
            do {
                let response = try JSONDecoder().decode(AccountResponse.self, from: data)
                let accounts = response.dataBundle ?? []
                
                CacheManager.shared.save(accounts, forKey: cacheKey)
                
                if let sharedDefaults = UserDefaults(suiteName: AppConstants.suiteName) {
                    let phoneNumbers = accounts.map { $0.telephoneno }
                    sharedDefaults.set(phoneNumbers, forKey: AppConstants.Keys.cachedAccounts)
                }
                
                return accounts
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response string"
                throw APIError.decodingFailed(message: error.localizedDescription, rawResponse: rawResponse)
            }
        } catch {
            if let cached: [AccountInfo] = CacheManager.shared.load(forKey: cacheKey, ignoreExpiration: true) {
                return cached
            }
            throw error
        }
    }
    
    func fetchServiceDetails(telephoneNo: String, forceRefresh: Bool = false) async throws -> ServiceDetailBundle? {
        let cacheKey = "serviceDetails_\(telephoneNo)"
        
        if !forceRefresh, let cached: ServiceDetailBundle = CacheManager.shared.load(forKey: cacheKey) {
            return cached
        }
        
        let url = URL(string: "\(AppConstants.API.baseURL)/AccountOMNI/GetServiceDetailRequest?categoryID=BB&telephoneNo=\(telephoneNo)")!
        
        do {
            let request = try createRequest(url: url)
            let (data, _) = try await execute(request: request)
            
            do {
                let response = try JSONDecoder().decode(ServiceDetailResponse.self, from: data)
                if let bundle = response.dataBundle {
                    CacheManager.shared.save(bundle, forKey: cacheKey)
                }
                return response.dataBundle
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response string"
                throw APIError.decodingFailed(message: error.localizedDescription, rawResponse: rawResponse)
            }
        } catch {
            if let cached: ServiceDetailBundle = CacheManager.shared.load(forKey: cacheKey, ignoreExpiration: true) {
                return cached
            }
            throw error
        }
    }
    
    func fetchUsageSummary(subscriberID: String, forceRefresh: Bool = false) async throws -> UsageSummaryBundle? {
        let cacheKey = "usageSummary_\(subscriberID)"
        
        if !forceRefresh, let cached: UsageSummaryBundle = CacheManager.shared.load(forKey: cacheKey) {
            return cached
        }
        
        let internationalNumber = convertToInternationalFormat(subscriberID)
        let url = APIEndpoint.usageSummary(subscriberID: internationalNumber).url
        
        do {
            let request = try createRequest(url: url)
            let (data, _) = try await execute(request: request)
            
            do {
                let response = try JSONDecoder().decode(UsageSummaryResponse.self, from: data)
                if let bundle = response.dataBundle {
                    CacheManager.shared.save(bundle, forKey: cacheKey)
                }
                return response.dataBundle
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response string"
                throw APIError.decodingFailed(message: error.localizedDescription, rawResponse: rawResponse)
            }
        } catch {
            if let cached: UsageSummaryBundle = CacheManager.shared.load(forKey: cacheKey, ignoreExpiration: true) {
                return cached
            }
            throw error
        }
    }
    
    func fetchVASBundles(subscriberID: String, forceRefresh: Bool = false) async throws -> [UsageDetail] {
        let cacheKey = "vasBundles_\(subscriberID)"
        
        if !forceRefresh, let cached: [UsageDetail] = CacheManager.shared.load(forKey: cacheKey) {
            return cached
        }
        
        let internationalNumber = convertToInternationalFormat(subscriberID)
        let url = APIEndpoint.vasBundles(subscriberID: internationalNumber).url
        
        do {
            let request = try createRequest(url: url)
            let (data, _) = try await execute(request: request)
            
            do {
                let response = try JSONDecoder().decode(UsageDataResponse.self, from: data)
                let bundles = response.dataBundle?.usageDetails ?? []
                CacheManager.shared.save(bundles, forKey: cacheKey)
                return bundles
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response string"
                throw APIError.decodingFailed(message: error.localizedDescription, rawResponse: rawResponse)
            }
        } catch {
            if let cached: [UsageDetail] = CacheManager.shared.load(forKey: cacheKey, ignoreExpiration: true) {
                return cached
            }
            throw error
        }
    }
    func fetchCurrentDailyUsage(subscriberID: String, billDate: String = "01", forceRefresh: Bool = false) async throws -> DailyUsageDataBundle? {
        let cacheKey = "currentDailyUsage_\(subscriberID)_\(billDate)"
        
        if !forceRefresh, let cached: DailyUsageDataBundle = DiskCacheManager.shared.load(forKey: cacheKey, isCurrentMonth: true) {
            return cached
        }
        
        let internationalNumber = convertToInternationalFormat(subscriberID)
        let url = APIEndpoint.currentDailyUsage(subscriberID: internationalNumber, billDate: billDate).url
        let request = try createRequest(url: url)
        
        let (data, _) = try await execute(request: request)
        let response = try JSONDecoder().decode(DailyUsageResponse.self, from: data)
        return response.dataBundle
    }
        if let bundle = response.dataBundle {
            DiskCacheManager.shared.save(bundle, forKey: cacheKey)
        }
    
    func fetchPreviousDailyUsage(subscriberID: String, billDate: String = "01", monthIndex: Int, forceRefresh: Bool = false) async throws -> DailyUsageDataBundle? {
        let cacheKey = "previousDailyUsage_\(subscriberID)_\(billDate)_\(monthIndex)"
        
        if !forceRefresh, let cached: DailyUsageDataBundle = DiskCacheManager.shared.load(forKey: cacheKey, isCurrentMonth: false) {
            return cached
        }
        
        let internationalNumber = convertToInternationalFormat(subscriberID)
        let url = APIEndpoint.previousDailyUsage(subscriberID: internationalNumber, billDate: billDate, monthIndex: monthIndex).url
        let request = try createRequest(url: url)
        
        let (data, _) = try await execute(request: request)
        let response = try JSONDecoder().decode(DailyUsageResponse.self, from: data)
        return response.dataBundle
    }
        if let bundle = response.dataBundle {
            DiskCacheManager.shared.save(bundle, forKey: cacheKey)
        }
    
    func fetchProtocolReport(subscriberID: String, date: String, forceRefresh: Bool = false) async throws -> ProtocolReportBundle? {
        let cacheKey = "protocolReport_\(subscriberID)_\(date)"
        
        if !forceRefresh, let cached: ProtocolReportBundle = DiskCacheManager.shared.load(forKey: cacheKey, isCurrentMonth: false) {
            return cached
        }
        
        let internationalNumber = convertToInternationalFormat(subscriberID)
        let url = APIEndpoint.protocolReport(subscriberID: internationalNumber, date: date).url
        let request = try createRequest(url: url)
        
        let (data, _) = try await execute(request: request)
        let response = try JSONDecoder().decode(ProtocolReportResponse.self, from: data)
        return response.dataBundle
    }
        if let bundle = response.dataBundle {
            DiskCacheManager.shared.save(bundle, forKey: cacheKey)
        }
    
    // MARK: - Private Helpers
    // Helper function to convert phone number to international format
    private func convertToInternationalFormat(_ phoneNumber: String) -> String {
        let cleaned = phoneNumber.replacingOccurrences(of: " ", with: "")
                                 .replacingOccurrences(of: "-", with: "")
        
        let letters = CharacterSet.letters
        if cleaned.rangeOfCharacter(from: letters) != nil {
            return cleaned
        }
        
        if cleaned.hasPrefix("0") {
            return "94" + cleaned.dropFirst()
        }
        if cleaned.hasPrefix("94") {
            return cleaned
        }
        return "94" + cleaned
    }
    
    private func createBaseRequest(url: URL, method: String = "GET", isUrlEncoded: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(AppConstants.API.clientId, forHTTPHeaderField: "X-Ibm-Client-Id")
        if isUrlEncoded {
            request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    private func createRequest(url: URL) throws -> URLRequest {
        guard let token = accessToken else {
            throw URLError(.userAuthenticationRequired)
        }
        
        var request = createBaseRequest(url: url, method: "GET")
        request.setValue("bearer \(token)", forHTTPHeaderField: "authorization")
        return request
    }
    
    private func execute(request: URLRequest) async throws -> (Data, URLResponse) {
        let originalAuthHeader = request.value(forHTTPHeaderField: "authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            AuthLog.log("transport error on \(request.url?.path ?? "?"): \(error.localizedDescription)")
            throw error
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            #if DEBUG
            if originalAuthHeader == "bearer expired-test-token" {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<non-utf8>"
                AuthLog.log("DEBUG probe \(request.url?.path ?? "?") -> HTTP \(httpResponse.statusCode) body=\(bodyPreview)")
            }
            #endif
            
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Token expired. Let's try to refresh automatically!
                
                // First, check if another process (e.g. Widget) has already refreshed the token
                if let currentToken = KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken),
                   "bearer \(currentToken)" != originalAuthHeader {
                    print("NetworkManager: Token already refreshed by another process. Retrying...")
                    var retriedRequest = request
                    retriedRequest.setValue("bearer \(currentToken)", forHTTPHeaderField: "authorization")
                    return try await session.data(for: retriedRequest)
                }
                
                AuthLog.log("HTTP \(httpResponse.statusCode) from \(request.url?.path ?? "?"); attempting refresh")
                do {
                    let newAccessToken = try await TokenRefresher.shared.refresh(using: self, failedAuthHeader: originalAuthHeader)
                    
                    // Re-create request with the fresh token
                    var retriedRequest = request
                    retriedRequest.setValue("bearer \(newAccessToken)", forHTTPHeaderField: "authorization")
                    return try await session.data(for: retriedRequest)
                } catch {
                    // Another process may have refreshed while we were failing
                    if let currentToken = KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken),
                       "bearer \(currentToken)" != originalAuthHeader {
                        AuthLog.log("refresh failed (\(error.localizedDescription)) but keychain holds a newer token; retrying with it")
                        var retriedRequest = request
                        retriedRequest.setValue("bearer \(currentToken)", forHTTPHeaderField: "authorization")
                        return try await session.data(for: retriedRequest)
                    }
                    
                    let nsError = error as NSError
                    // Only a definitive rejection of the refresh token ends the session.
                    // Network errors / 5xx / decoding problems must never log the user out.
                    if nsError.domain == "Auth", nsError.code == 400 || nsError.code == 401 {
                        if AuthLog.isExtension {
                            // The widget must not wipe the shared keychain; the app decides.
                            AuthLog.log("refresh rejected (\(nsError.code)) in widget; NOT wiping credentials")
                        } else {
                            logout(reason: "refresh token rejected: \(nsError.localizedDescription)")
                        }
                    } else {
                        AuthLog.log("refresh failed transiently, keeping session: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
                    }
                    throw URLError(.userAuthenticationRequired)
                }
            } else if !(200...299).contains(httpResponse.statusCode) {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<non-utf8>"
                AuthLog.log("HTTP \(httpResponse.statusCode) from \(request.url?.path ?? "?") body=\(bodyPreview)")
            }
        }
        
        return (data, response)
    }
    
    // MARK: - Token Refresh
    
    func performTokenRefresh(failedAuthHeader: String? = nil) async throws -> String {
        // Serialise across app + widget processes: refresh tokens may be single-use (rotating).
        return try await CrossProcessLock.withLock {
            // Someone else (the other process) may have refreshed while we waited for the lock.
            if let failed = failedAuthHeader,
               let current = KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken),
               "bearer \(current)" != failed {
                AuthLog.log("refresh skipped: token already renewed by another process")
                return current
            }
            
            let refreshRead = KeychainHelper.shared.readWithStatus(forKey: AppConstants.Keys.refreshToken)
            let usernameRead = KeychainHelper.shared.readWithStatus(forKey: AppConstants.Keys.username)
            guard let refreshToken = refreshRead.value, let username = usernameRead.value else {
                AuthLog.log("refresh impossible: refreshToken status=\(refreshRead.status) username status=\(usernameRead.status)")
                if refreshRead.status == errSecItemNotFound || usernameRead.status == errSecItemNotFound {
                    throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No stored refresh token"])
                }
                throw URLError(.userAuthenticationRequired) // keychain temporarily unreadable (e.g. device locked)
            }
            
            let url = APIEndpoint.refreshToken.url
            var request = createBaseRequest(url: url, method: "POST", isUrlEncoded: true)
            
            let encodedToken = percentEncode(refreshToken)
            let encodedUsername = percentEncode(username)
            let body = "username=\(encodedUsername)&refreshToken=\(encodedToken)&channelID=WEB"
            request.httpBody = body.data(using: .utf8)
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
                
                // Persist the (possibly rotated) refresh token FIRST: if we are killed between the
                // two writes, the old access token is merely stale, but a lost refresh token is fatal.
                if let newRefreshToken = loginResponse.refreshToken {
                    KeychainHelper.shared.save(newRefreshToken, forKey: AppConstants.Keys.refreshToken)
                }
                KeychainHelper.shared.save(loginResponse.accessToken, forKey: AppConstants.Keys.accessToken)
                
                AuthLog.log("refresh OK; refreshToken \(loginResponse.refreshToken == nil ? "NOT returned" : (loginResponse.refreshToken == refreshToken ? "unchanged" : "rotated"))")
                return loginResponse.accessToken
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                AuthLog.log("refresh rejected: HTTP \(httpResponse.statusCode) body=\(responseString.prefix(300))")
                throw NSError(domain: "Auth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed with status \(httpResponse.statusCode): \(responseString)"])
            }
        }
    }
}

// MARK: - TokenRefresher Actor

actor TokenRefresher {
    static let shared = TokenRefresher()
    private init() {
        KeychainHelper.shared.migrateFromSyncedKeychainIfNeeded()
    }
    
    private var activeTask: Task<String, Error>?
    
    func refresh(using manager: NetworkManager, failedAuthHeader: String? = nil) async throws -> String {
        // If a refresh is already in progress, await its result
        if let existingTask = activeTask {
            return try await existingTask.value
        }
        
        // Spawn a new task to perform the refresh
        let task = Task<String, Error> {
            defer {
                self.activeTask = nil
            }
            return try await manager.performTokenRefresh(failedAuthHeader: failedAuthHeader)
        }
        
        activeTask = task
        return try await task.value
    }
}

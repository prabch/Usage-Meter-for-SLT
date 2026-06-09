//
//  Models.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2026-01-06.
//

import Foundation
import SwiftUI

// MARK: - Auth Response
struct LoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let name: String?
    let userId: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case name
        case userId = "user_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode accessToken: try camelCase first, fallback to snake_case
        if let token = try? container.decode(String.self, forKey: .accessToken) {
            self.accessToken = token
        } else {
            self.accessToken = try container.decode(String.self, forKey: .accessTokenSnake)
        }
        
        // Decode refreshToken: try camelCase first, fallback to snake_case
        if let token = try? container.decode(String.self, forKey: .refreshToken) {
            self.refreshToken = token
        } else {
            self.refreshToken = try container.decode(String.self, forKey: .refreshTokenSnake)
        }
        
        self.name = try? container.decode(String.self, forKey: .name)
        self.userId = try? container.decode(String.self, forKey: .userId)
    }
}

// MARK: - Account Info
struct AccountResponse: Codable {
    let isSuccess: Bool
    let dataBundle: [AccountInfo]?
}

struct AccountInfo: Codable, Identifiable, Hashable {
    var id: String { accountno }
    let accountno: String
    let telephoneno: String
    let status: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(accountno)
    }
    
    static func == (lhs: AccountInfo, rhs: AccountInfo) -> Bool {
        lhs.accountno == rhs.accountno
    }
}

// MARK: - Service Details
struct ServiceDetailResponse: Codable {
    let isSuccess: Bool
    let dataBundle: ServiceDetailBundle?
}

struct ServiceDetailBundle: Codable, Equatable {
    let accountNo: String
    let promotionName: String?
    let contactNamewithInit: String?
    let listofBBService: [BBService]
    
    enum CodingKeys: String, CodingKey {
        case accountNo, promotionName, contactNamewithInit, listofBBService
    }
    
    static func == (lhs: ServiceDetailBundle, rhs: ServiceDetailBundle) -> Bool {
        return lhs.accountNo == rhs.accountNo
    }
}

struct BBService: Codable, Identifiable, Equatable {
    var id: String { serviceID }
    let serviceID: String
    let packageName: String
    let serviceStatus: String
    let serviceType: String
}

// MARK: - Usage Summary
struct UsageSummaryResponse: Codable {
    let isSuccess: Bool
    let dataBundle: UsageSummaryBundle?
}

struct UsageSummaryBundle: Codable, Equatable {
    let status: String
    let myPackageSummary: PackageSummary?
    let bonusDataSummary: PackageSummary?
    let extraGbDataSummary: PackageSummary?
    let myPackageInfo: PackageInfo?
    
    enum CodingKeys: String, CodingKey {
        case status
        case myPackageSummary = "my_package_summary"
        case bonusDataSummary = "bonus_data_summary"
        case extraGbDataSummary = "extra_gb_data_summary"
        case myPackageInfo = "my_package_info"
    }
    
    static func == (lhs: UsageSummaryBundle, rhs: UsageSummaryBundle) -> Bool {
        // Simple equality check based on status for now, deep comparison if needed
        return lhs.status == rhs.status &&
               lhs.myPackageInfo?.packageName == rhs.myPackageInfo?.packageName
    }
    
    var statusColor: Color {
        switch status.uppercased() {
        case "NORMAL", "ACTIVE":
            return .green
        case "THROTTLED":
            return .red
        default:
            return .gray
        }
    }
}

struct PackageSummary: Codable, Equatable {
    let limit: String?
    let used: String
    let volumeUnit: String
    
    enum CodingKeys: String, CodingKey {
        case limit, used
        case volumeUnit = "volume_unit"
    }
}

struct PackageInfo: Codable, Equatable {
    let packageName: String
    let usageDetails: [UsageDetail]
    
    enum CodingKeys: String, CodingKey {
        case packageName = "package_name"
        case usageDetails
    }
}

// MARK: - Usage Details (VAS & General)
struct UsageDataResponse: Codable {
    let isSuccess: Bool
    let dataBundle: DataBundle?
    
    enum CodingKeys: String, CodingKey {
        case isSuccess, dataBundle
    }
}

struct DataBundle: Codable {
    let usageDetails: [UsageDetail]?
    let packageSummary: PackageSummary?
    let reportedTime: String?
    
    enum CodingKeys: String, CodingKey {
        case usageDetails
        case packageSummary = "package_summary"
        case reportedTime = "reported_time"
    }
}

struct UsageDetail: Codable, Identifiable, Equatable {
    let id = UUID()
    let name: String
    let limit: String?
    let remaining: String?
    let used: String
    let percentage: Int
    let volumeUnit: String
    let expiryDate: String?
    let subscriptionId: String?
    let timestamp: Int
    let unsubscribable: Bool
    let claim: String?
    
    init(name: String, limit: String?, remaining: String?, used: String, percentage: Int, volumeUnit: String, expiryDate: String?, subscriptionId: String?, timestamp: Int, unsubscribable: Bool, claim: String?) {
        self.name = name
        self.limit = limit
        self.remaining = remaining
        self.used = used
        self.percentage = percentage
        self.volumeUnit = volumeUnit
        self.expiryDate = expiryDate
        self.subscriptionId = subscriptionId
        self.timestamp = timestamp
        self.unsubscribable = unsubscribable
        self.claim = claim
    }
    
    enum CodingKeys: String, CodingKey {
        case name, limit, remaining, used, percentage
        case volumeUnit = "volume_unit"
        case expiryDate = "expiry_date"
        case subscriptionId = "subscriptionid"
        case timestamp, unsubscribable, claim
    }
    
    static func == (lhs: UsageDetail, rhs: UsageDetail) -> Bool {
        return lhs.name == rhs.name && lhs.used == rhs.used && lhs.limit == rhs.limit
    }
}

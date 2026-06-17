//
//  AppIntent.swift
//  SLT Usage Meter Widget
//
//  Created by Prabhashwara on 28-12-2025.
//

import WidgetKit
import AppIntents

@available(macOS 14.0, *)
@available(iOS 17.0, *)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "Select the account to display usage for." }

    @Parameter(title: "Account")
    var account: SubscriberEntity?

    @Parameter(title: "Hide Phone Number", default: false)
    var hidePhoneNumber: Bool
    
    @Parameter(title: "Hide Connection Status", default: false)
    var hideConnectionStatus: Bool
    
    @Parameter(title: "Invert Progress Bar", default: false)
    var invertProgressBar: Bool
}

@available(iOS 16.0, macOS 13.0, *)
struct SubscriberEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static var defaultQuery = SubscriberQuery()
    
    var id: String
    var telephoneNo: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(telephoneNo)")
    }
    
    init(id: String, telephoneNo: String) {
        self.id = id
        self.telephoneNo = telephoneNo
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct SubscriberQuery: EntityQuery {
    func entities(for identifiers: [SubscriberEntity.ID]) async throws -> [SubscriberEntity] {
        let accounts = try? await NetworkManager.shared.fetchAccounts()
        return accounts?.filter { identifiers.contains($0.telephoneno) }
            .map { SubscriberEntity(id: $0.telephoneno, telephoneNo: $0.telephoneno) } ?? []
    }
    
    func suggestedEntities() async throws -> [SubscriberEntity] {
        let accounts = try? await NetworkManager.shared.fetchAccounts()
        return accounts?.map { SubscriberEntity(id: $0.telephoneno, telephoneNo: $0.telephoneno) } ?? []
    }
    
    func defaultResult() async -> SubscriberEntity? {
        try? await suggestedEntities().first
    }
}

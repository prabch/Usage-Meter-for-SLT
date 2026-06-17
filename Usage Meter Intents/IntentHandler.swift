//
//  IntentHandler.swift
//  Usage Meter Intents
//
//  Created by Prabhashwara Chandrapadma on 17-06-2026.
//

import Intents

class IntentHandler: INExtension, LegacyConfigurationIntentHandling {
    
    override func handler(for intent: INIntent) -> Any {
        return self
    }
    
    func provideAccountOptionsCollection(for intent: LegacyConfigurationIntent, with completion: @escaping (INObjectCollection<NSString>?, Error?) -> Void) {
        let sharedDefaults = UserDefaults(suiteName: AppConstants.suiteName)
        let cachedPhones = sharedDefaults?.stringArray(forKey: AppConstants.Keys.cachedAccounts) ?? []
        
        if !cachedPhones.isEmpty {
            let phoneNumbers = cachedPhones.map { NSString(string: $0) }
            let collection = INObjectCollection(items: phoneNumbers)
            completion(collection, nil)
            return
        }
        
        Task {
            do {
                let accounts = try await NetworkManager.shared.fetchAccounts()
                let phoneNumbers = accounts.map { NSString(string: $0.telephoneno) }
                let collection = INObjectCollection(items: phoneNumbers)
                completion(collection, nil)
            } catch {
                completion(nil, error)
            }
        }
    }
    
    func defaultAccount(for intent: LegacyConfigurationIntent) -> String? {
        // Provide the first account as default synchronously if possible, or nil
        return nil
    }
}

//
//  ContentView.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2024-06-30.
//

import SwiftUI
import WidgetKit
import Security


struct ContentView: View {
    @State private var isLoggedIn: Bool = false
    @State private var accessToken: String?
    @State private var requestedAccountID: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isLoggedIn {
                MainView(accessToken: accessToken ?? "", logoutAction: logout, requestedAccountID: $requestedAccountID)
            } else {
                LoginView(loginAction: { token in
                    print("ContentView: Login successful. Received token: \(token)")
                    self.accessToken = token
                    self.isLoggedIn = true

                    // Store accessToken securely in Keychain
                    KeychainHelper.shared.save(token, forKey: AppConstants.Keys.accessToken)
                    print("ContentView: Access token stored securely in shared Keychain.")
                    
                    // Reload widget timelines
                    WidgetCenter.shared.reloadAllTimelines()
                })
            }
        }
        .onAppear {
            // Check for stored credentials on app launch
            checkStoredCredentials()
            
            // Listen for token expiration notifications
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("TokenExpired"),
                object: nil,
                queue: .main
            ) { _ in
                print("ContentView: Token expired notification received. Logging out...")
                logout()
            }
        }
        .onChange(of: scenePhase) { phase in
            // Re-sync with the keychain whenever we come to the foreground: the widget may have
            // renewed the tokens, or a launch-time read may have failed transiently.
            if phase == .active { checkStoredCredentials() }
        }
        .onOpenURL { url in
            if url.scheme == "sltusage" && url.host == "account" {
                let accountID = url.lastPathComponent
                print("ContentView: Opened from widget with account ID: \(accountID)")
                self.requestedAccountID = accountID
            }
        }
    }
    
    private func checkStoredCredentials() {
        print("ContentView: Checking for stored credentials in Keychain...")
        KeychainHelper.shared.migrateFromSyncedKeychainIfNeeded()
        
        let defaults = UserDefaults(suiteName: AppConstants.suiteName)
        let wasSignedIn = defaults?.bool(forKey: AppConstants.Keys.wasSignedIn) ?? false
        let tokenRead = KeychainHelper.shared.readWithStatus(forKey: AppConstants.Keys.accessToken)
        let userRead = KeychainHelper.shared.readWithStatus(forKey: AppConstants.Keys.username)
        
        if let storedAccessToken = tokenRead.value, let storedUsername = userRead.value {
            print("ContentView: Found stored credentials for user: \(storedUsername)")
            defaults?.set(true, forKey: AppConstants.Keys.wasSignedIn)
            if !isLoggedIn {
                AuthLog.log("credentials found; restoring signed-in state")
            }
            self.accessToken = storedAccessToken
            self.isLoggedIn = true
        } else {
            if wasSignedIn || isLoggedIn || tokenRead.status != errSecItemNotFound || userRead.status != errSecItemNotFound {
                AuthLog.log("showing login (wasSignedIn=\(wasSignedIn)): accessToken status=\(tokenRead.status) username status=\(userRead.status)")
            }
            self.isLoggedIn = false
        }
    }

    private func logout() {
        print("ContentView: Logout triggered.")
        AuthLog.log("ContentView.logout() invoked (user tap or TokenExpired notification)")
        UserDefaults(suiteName: AppConstants.suiteName)?.set(false, forKey: AppConstants.Keys.wasSignedIn)
        KeychainHelper.shared.delete(forKey: AppConstants.Keys.accessToken)
        KeychainHelper.shared.delete(forKey: AppConstants.Keys.refreshToken)
        KeychainHelper.shared.delete(forKey: AppConstants.Keys.username)
        print("ContentView: Tokens and username removed from secure Keychain.")
        
        self.accessToken = nil
        self.isLoggedIn = false
        print("ContentView: isLoggedIn set to false.")
        
        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}





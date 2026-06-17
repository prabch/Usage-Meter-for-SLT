//
//  ContentView.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2024-06-30.
//

import SwiftUI
import WidgetKit


struct ContentView: View {
    @State private var isLoggedIn: Bool = false
    @State private var accessToken: String?
    @State private var requestedAccountID: String?

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
        
        // Check if we have a stored access token and username in Keychain
        if let storedAccessToken = KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken),
           let storedUsername = KeychainHelper.shared.read(forKey: AppConstants.Keys.username) {
            print("ContentView: Found stored credentials for user: \(storedUsername)")
            self.accessToken = storedAccessToken
            self.isLoggedIn = true
        } else {
            print("ContentView: No stored credentials found. Showing login screen.")
            self.isLoggedIn = false
        }
    }

    private func logout() {
        print("ContentView: Logout triggered.")
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





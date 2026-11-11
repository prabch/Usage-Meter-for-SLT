//
//  AccountView.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2024-01-06.
//

import SwiftUI
import WidgetKit

struct AccountView: View {
    let serviceDetail: ServiceDetailBundle?
    let logoutAction: () -> Void
    
    @State private var showingLogoutConfirmation = false
    
    @AppStorage("invertProgressBar", store: UserDefaults(suiteName: "group.com.prabch.sltusage"))
    private var invertProgressBar: Bool = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                if let service = serviceDetail {
                    ServiceInfoCard(service: service)
                        .padding(.top)
                } else {
                    Text("Service details unavailable")
                        .foregroundColor(.secondary)
                        .padding(.top, 50)
                }
                
                // Preferences Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preferences")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Invert Progress Bars")
                                Text("Shows remaining usage instead of used usage.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("Invert Progress Bars", isOn: $invertProgressBar)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding()
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal)
                    
                    Text("To customize preferences for individual widgets, press and hold a widget on your Home Screen and select 'Edit Widget'.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Button(action: {
                    showingLogoutConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                    .foregroundColor(.white)
                    #if os(macOS)
                    .frame(maxWidth: 300)
                    #else
                    .frame(maxWidth: .infinity)
                    #endif
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .confirmationDialog("Are you sure you want to log out?", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                    Button("Log Out", role: .destructive) {
                        logoutAction()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You will be logged out on this device.")
                }
                
                // About & Disclaimer Section
                VStack(spacing: 12) {
                    Text("Usage Meter for SLT is an independent app and is not affiliated with or endorsed by SLT Mobitel")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("•••")
                        .font(.footnote)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("This project is open source; you can view and audit the code on [GitHub](https://github.com/prabch/Usage-Meter-for-SLT).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("No personal data is collected or stored externally; login credentials are used only to obtain a secure token, which is stored securely in your device's Keychain.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 4)
                    
                    Text("Version \(appVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 4)
                    
                    #if DEBUG
                    AuthDiagnosticsButton()
                    DebugTokenExpiryButton()
                    #endif
                    
                    Link(destination: URL(string: "https://prabch.com")!) {
                        HStack(spacing: 6) {
                            Image("favicon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .cornerRadius(4)
                            
                            Text("prabch.com")
                                .font(.footnote)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                Spacer()
            }
            .padding(.vertical)
        }
    }
}


#if DEBUG
/// Copies the shared auth event log (no secrets) to the clipboard so it can be pasted into a bug report.
struct AuthDiagnosticsButton: View {
    @State private var copied = false
    
    var body: some View {
        Button(copied ? "Copied auth log" : "Copy auth diagnostics") {
            let text = AuthLog.read()
            #if os(iOS)
            UIPasteboard.general.string = text
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            copied = true
        }
        .font(.caption2)
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }
}

/// Debug-only helper to test token expiry/refresh and widget reload without editing code.
private struct DebugTokenExpiryButton: View {
    @State private var isTesting = false
    @State private var statusText: String?
    
    var body: some View {
        VStack(spacing: 6) {
            Button(isTesting ? "Testing..." : "Simulate Expired Token (Debug)") {
                runExpiryTest()
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            .disabled(isTesting)
            
            Button(isTesting ? "Testing..." : "Test Direct Refresh (Debug)") {
                runDirectRefreshTest()
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            .disabled(isTesting)
            
            if let statusText = statusText {
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func runExpiryTest() {
        isTesting = true
        statusText = nil
        
        let existingToken = KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken)
        let previousValidToken = (existingToken != "expired-test-token") ? existingToken : nil
        
        KeychainHelper.shared.save("expired-test-token", forKey: AppConstants.Keys.accessToken)
        AuthLog.log("DEBUG: forced expired access token")
        WidgetCenter.shared.reloadAllTimelines()
        
        Task {
            do {
                let accounts = try await NetworkManager.shared.fetchAccounts(forceRefresh: true)
                let current = KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken)
                let renewed = current != nil && current != "expired-test-token"
                if !renewed, let restore = previousValidToken {
                    KeychainHelper.shared.save(restore, forKey: AppConstants.Keys.accessToken)
                }
                AuthLog.log("DEBUG: test fetchAccounts returned \(accounts.count) accounts, renewed=\(renewed)")
                await MainActor.run {
                    statusText = renewed ? "Refresh succeeded — copy auth diagnostics to inspect" : "Token was not renewed (likely non-401 response) — check auth diagnostics"
                    isTesting = false
                }
            } catch {
                if let restore = previousValidToken,
                   KeychainHelper.shared.read(forKey: AppConstants.Keys.accessToken) == "expired-test-token" {
                    KeychainHelper.shared.save(restore, forKey: AppConstants.Keys.accessToken)
                }
                AuthLog.log("DEBUG: test fetchAccounts threw \(error.localizedDescription)")
                await MainActor.run {
                    statusText = "Failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
    
    private func runDirectRefreshTest() {
        isTesting = true
        statusText = nil
        AuthLog.log("DEBUG: invoking direct TokenRefresher.refresh")
        
        Task {
            do {
                _ = try await TokenRefresher.shared.refresh(using: NetworkManager.shared)
                await MainActor.run {
                    statusText = "Direct refresh succeeded — copy auth diagnostics to inspect"
                    isTesting = false
                }
            } catch {
                AuthLog.log("DEBUG: direct refresh threw \(error.localizedDescription)")
                await MainActor.run {
                    statusText = "Direct refresh failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}
#endif

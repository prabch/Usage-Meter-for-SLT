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
    
    @AppStorage("hidePhoneNumberInWidget", store: UserDefaults(suiteName: "group.com.prabch.sltusage"))
    private var hidePhoneNumberInWidget: Bool = false
    
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
                            Text("Hide Phone Number")
                            Spacer()
                            Toggle("Hide Phone Number", isOn: $hidePhoneNumberInWidget)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .padding()
                        
                        Divider()
                            .padding(.leading)
                        
                        HStack {
                            Text("Invert Progress Bars")
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
                    Text("You will be logged out of all devices on your Apple ID.")
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
        .onChange(of: hidePhoneNumberInWidget) { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: invertProgressBar) { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

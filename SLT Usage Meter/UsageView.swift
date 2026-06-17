//
//  UsageView.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2024-01-06.
//

import SwiftUI
#if os(iOS)
import MessageUI
#endif

struct UsageView: View {
    let usageSummary: UsageSummaryBundle?
    let vasBundles: [UsageDetail]
    let isLoading: Bool
    let errorMessage: String?
    let rawErrorResponse: String?
    let retryAction: () -> Void
    let refreshAction: () async -> Void
    
    @Environment(\.openURL) var openURL
    
    #if os(iOS)
    @State private var isShowingMailView = false
    #endif
    
    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Fetching usage data...")
                    Spacer()
                }
            } else if let error = errorMessage {
                VStack(spacing: 15) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") {
                        retryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let rawResponse = rawErrorResponse {
                        let emailBody = """
                        Hi Prab,

                        I ran into an issue while trying to load my connection usage in the Usage Meter for SLT app.

                        To help you troubleshoot, I've attached the raw API response from SLT as a JSON file. Please note that this file only contains the error response and does not include any authentication tokens or sensitive personal details.

                        Thanks!
                        """
                        
                        let fallbackResponse = rawResponse.count > 1500 ? String(rawResponse.prefix(1500)) + "\n...[truncated]" : rawResponse
                        let fallbackBody = """
                        Hi Prab,

                        I ran into an issue while trying to load my connection usage in the Usage Meter for SLT app.

                        To help you troubleshoot, here is the raw API response from SLT (this does not include any authentication tokens or sensitive personal details):

                        \(fallbackResponse)

                        Thanks!
                        """
                        
                        let encodedFallbackBody = fallbackBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

                        Button("Report Issue") {
                            #if os(iOS)
                            if MFMailComposeViewController.canSendMail() {
                                isShowingMailView = true
                            } else {
                                if let url = URL(string: "mailto:hi@prabch.com?subject=Usage%20Meter%20for%20SLT%20Error&body=\(encodedFallbackBody)") {
                                    openURL(url)
                                }
                            }
                            #else
                            if let url = URL(string: "mailto:hi@prabch.com?subject=Usage%20Meter%20for%20SLT%20Error&body=\(encodedFallbackBody)") {
                                openURL(url)
                            }
                            #endif
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 10)
                        #if os(iOS)
                        .sheet(isPresented: $isShowingMailView) {
                            MailView(isShowing: $isShowingMailView) { vc in
                                vc.setToRecipients(["hi@prabch.com"])
                                vc.setSubject("Usage Meter for SLT API Error Response")
                                vc.setMessageBody(emailBody, isHTML: false)
                                if let data = rawResponse.data(using: .utf8) {
                                    vc.addAttachmentData(data, mimeType: "application/json", fileName: "api_response.json")
                                }
                            }
                        }
                        #endif
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Status Header
                        if let summary = usageSummary {
                            // Status Card
                            UsageSummaryCard(summary: summary)
                                .padding(.top)
                            
                            // Main Usage Bars
                            if let packageInfo = summary.myPackageInfo {
                                VStack(alignment: .leading, spacing: 15) {
                                    Text(packageInfo.packageName)
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    ForEach(packageInfo.usageDetails) { usage in
                                        UsageProgressBar(usage: usage)
                                    }
                                }
                                .padding(.vertical)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                                .padding(.horizontal)
                            }
                            
                            // Data Packs (Bonus/Extra)
                            UsageBreakdownView(summary: summary)
                        } else {
                            // Fallback if no usage summary
                            Text("No usage data available")
                                .foregroundColor(.secondary)
                                .padding()
                                .padding(.top, 50)
                        }
                        
                        // VAS / Add-on Bundles
                        if !vasBundles.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Add-on Bundles")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                
                                ForEach(vasBundles) { bundle in
                                    VASBundleRow(bundle: bundle)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                #if os(iOS)
                .refreshable {
                    await refreshAction()
                }
                #endif
            }
        }
    }
}

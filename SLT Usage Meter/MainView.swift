//
//  MainView.swift
//  SLT Usage Meter
//
//  Created by Prabhashwara on 2024-06-30.
//

import SwiftUI

struct MainView: View {
    let accessToken: String
    let logoutAction: () -> Void
    
    @State private var accounts: [AccountInfo] = []
    @State private var selectedAccount: AccountInfo?
    @State private var serviceDetail: ServiceDetailBundle?
    @State private var usageSummary: UsageSummaryBundle?
    @State private var vasBundles: [UsageDetail] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    var body: some View {
        Group {
            #if os(iOS)
            NavigationView {
                tabbedContent
            }
            .navigationViewStyle(.stack)
            #else
            tabbedContent
            #endif
        }
        .onAppear {
            initialFetch()
        }
        .onChange(of: selectedAccount) { _ in
            fetchDataForSelectedAccount()
        }
    }

    private var tabbedContent: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // MacOS Custom Header
            HStack {
                Text("Usage Meter for SLT")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                
                Menu {
                    ForEach(accounts) { account in
                        Button(action: { selectedAccount = account }) {
                            if selectedAccount?.telephoneno == account.telephoneno {
                                Label(account.telephoneno, systemImage: "checkmark")
                            } else {
                                Text(account.telephoneno)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            TabView(selection: $selectedTab) {
                UsageView(
                    usageSummary: usageSummary,
                    vasBundles: vasBundles,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    retryAction: fetchDataForSelectedAccount,
                    refreshAction: refreshData
                )
                .tabItem {
                    Label("Summary", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

                DailyUsageView(subscriberID: selectedAccount?.telephoneno)
                .tabItem {
                    Label("Usage", systemImage: "chart.bar.fill")
                }
                .tag(1)

                AccountView(
                    serviceDetail: serviceDetail,
                    logoutAction: logoutAction
                )
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag(2)
            }
        }
        #else
        // iOS TabView with Toolbar
        TabView(selection: $selectedTab) {
            UsageView(
                usageSummary: usageSummary,
                vasBundles: vasBundles,
                isLoading: isLoading,
                errorMessage: errorMessage,
                retryAction: fetchDataForSelectedAccount,
                refreshAction: refreshData
            )
            .tabItem {
                Label("Summary", systemImage: "gauge.with.dots.needle.67percent")
            }
            .tag(0)

            DailyUsageView(subscriberID: selectedAccount?.telephoneno)
            .tabItem {
                Label("Usage", systemImage: "chart.bar.fill")
            }
            .tag(1)

            AccountView(
                serviceDetail: serviceDetail,
                logoutAction: logoutAction
            )
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
            .tag(2)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text("Usage Meter for SLT")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(accounts) { account in
                        Button(action: { selectedAccount = account }) {
                            if selectedAccount?.telephoneno == account.telephoneno {
                                Label(account.telephoneno, systemImage: "checkmark")
                            } else {
                                Text(account.telephoneno)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
        #endif
    }

    private func initialFetch() {
        isLoading = true
        errorMessage = nil
        
        // Check for login using NetworkManager (or check UserDefaults directly via helper)
        guard let _ = NetworkManager.shared.accessToken,
              let _ = NetworkManager.shared.username else {
            errorMessage = "Username not found. Please log in again."
            isLoading = false
            return
        }
        
        Task {
            do {
                let accs = try await NetworkManager.shared.fetchAccounts()
                DispatchQueue.main.async {
                    self.accounts = accs
                    if let first = accs.first {
                        self.selectedAccount = first
                    } else {
                        self.errorMessage = "No accounts found."
                        self.isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func fetchDataForSelectedAccount() {
        guard let account = selectedAccount else { return }
        
        isLoading = true
        errorMessage = nil
        
        let telephoneNo = account.telephoneno
        
        Task {
            do {
                // Fetch Service Details
                if let service = try await NetworkManager.shared.fetchServiceDetails(telephoneNo: telephoneNo) {
                     DispatchQueue.main.async { self.serviceDetail = service }
                } else {
                    // Handle case where service might be null but we proceed? 
                    // Or just log it. The original code errored out.
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to fetch service details."
                        self.isLoading = false
                    }
                    return
                }
                
                // Fetch Usage and VAS concurrently
                async let summary = NetworkManager.shared.fetchUsageSummary(subscriberID: telephoneNo)
                async let bundles = NetworkManager.shared.fetchVASBundles(subscriberID: telephoneNo)
                
                let (usageSummary, vasBundles) = try await (summary, bundles)
                
                DispatchQueue.main.async {
                    self.usageSummary = usageSummary
                    self.vasBundles = vasBundles
                    self.isLoading = false
                }
                
            } catch {
                 DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // Async wrapper for pull-to-refresh
    private func refreshData() async {
        await withCheckedContinuation { continuation in
            fetchDataForSelectedAccount()
            // Wait for loading to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }
}

// MARK: - UI Components
struct UsageProgressBar: View {
    let usage: UsageDetail
    
    var remainingPercentage: Double {
        guard let limitStr = usage.limit, let limit = Double(limitStr), limit > 0 else { return 0 }
        guard let used = Double(usage.used) else { return 0 }
        return max(0, 100 - (used / limit) * 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(usage.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 4) {
                    if usage.limit != nil {
                        Text("\(usage.used) / \(usage.limit ?? "0") \(usage.volumeUnit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(usage.used) \(usage.volumeUnit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Unlimited")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }
            }
            
            if usage.limit != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(1.0, (Double(usage.used) ?? 0) / (Double(usage.limit ?? "1") ?? 1)), height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            HStack {
                if let expiry = usage.expiryDate {
                    Text("Expires: \(expiry)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let remaining = usage.remaining, usage.limit != nil {
                    Text("Remaining: \(remaining) \(usage.volumeUnit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if usage.limit != nil {
                    Text(String(format: "%.0f%%", remainingPercentage))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct UsageSummaryCard: View {
    let summary: UsageSummaryBundle
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Connection Status")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(summary.status)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "wifi")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(summary.statusColor)
        .cornerRadius(16)
        .shadow(color: summary.statusColor.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

struct UsageBreakdownView: View {
    let summary: UsageSummaryBundle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.bonusDataSummary != nil || summary.extraGbDataSummary != nil {
                Text("Data Packs")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 15) {
                    if let bonus = summary.bonusDataSummary {
                        BreakdownCard(title: "Bonus Data", used: bonus.used, limit: bonus.limit, unit: bonus.volumeUnit, icon: "gift", color: .purple)
                    }
                    if let extra = summary.extraGbDataSummary {
                        BreakdownCard(title: "Extra GB", used: extra.used, limit: extra.limit, unit: extra.volumeUnit, icon: "plus.circle", color: .orange)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct BreakdownCard: View {
    let title: String
    let used: String
    let limit: String?
    let unit: String
    let icon: String
    let color: Color
    
    var remainingPercentage: Double {
        guard let limitStr = limit, let limitVal = Double(limitStr), limitVal > 0 else { return 0 }
        guard let usedVal = Double(used) else { return 0 }
        return max(0, 100 - (usedVal / limitVal) * 100)
    }
    
    var remaining: Double {
        guard let limitStr = limit, let limitVal = Double(limitStr), let usedVal = Double(used) else { return 0 }
        return max(0, limitVal - usedVal)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundColor(color)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Spacer()
                HStack(spacing: 4) {
                    if let limit = limit {
                        Text("\(used) / \(limit) \(unit)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(used) \(unit)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Unlimited")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }
            }
            
            if limit != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * min(1.0, (Double(used) ?? 0) / (Double(limit ?? "1") ?? 1)), height: 6)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Spacer()
                    Text("Remaining: \(String(format: "%.1f", remaining)) \(unit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", remainingPercentage))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }
}

struct VASBundleRow: View {
    let bundle: UsageDetail
    
    var remainingPercentage: Double {
        guard let limitStr = bundle.limit, let limit = Double(limitStr), limit > 0 else { return 0 }
        guard let used = Double(bundle.used) else { return 0 }
        return max(0, 100 - (used / limit) * 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(bundle.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 4) {
                    if bundle.limit != nil {
                        Text("\(bundle.used) / \(bundle.limit ?? "0") \(bundle.volumeUnit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(bundle.used) \(bundle.volumeUnit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Unlimited")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }
            }
            
            if bundle.limit != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(1.0, (Double(bundle.used) ?? 0) / (Double(bundle.limit ?? "1") ?? 1)), height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            HStack {
                if let expiry = bundle.expiryDate {
                    Text("Expires: \(expiry)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let remaining = bundle.remaining, bundle.limit != nil {
                    Text("Remaining: \(remaining) \(bundle.volumeUnit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if bundle.limit != nil {
                    Text(String(format: "%.0f%%", remainingPercentage))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

struct ServiceInfoCard: View {
    let service: ServiceDetailBundle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service Information")
                .font(.title3)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Account Name", value: service.contactNamewithInit ?? "")
                InfoRow(label: "Account No", value: service.accountNo)
                InfoRow(label: "Plan", value: service.promotionName ?? "")
                if let bb = service.listofBBService.first {
                    InfoRow(label: "Service ID", value: bb.serviceID)
                    InfoRow(label: "Service Type", value: bb.serviceType)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.05)))
        }
        .padding(.horizontal)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(accessToken: "sampleAccessToken", logoutAction: {})
    }
}


// MARK: - UsageCore Consolidated Code (Resolved Module Error)




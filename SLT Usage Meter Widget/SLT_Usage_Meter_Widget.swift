//
//  SLT_Usage_Meter_Widget.swift
//  SLT Usage Meter Widget
//
//  Created by Prabhashwara on 28-12-2025.
//

import WidgetKit
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: "0000000000")
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: "0112223333")
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let currentDate = Date()
        
        // 1. Check Login
        guard let _ = NetworkManager.shared.accessToken else {
             let entry = SimpleEntry(date: currentDate, isLoggedIn: false, usageSummary: nil, vasBundles: [], subscriberID: nil)
             return Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(3600)))
        }
        
        // 2. Determine Subscriber ID
        var subscriberID = configuration.account?.id
        if subscriberID == nil {
            // Fetch accounts to find a default
            if let accounts = try? await NetworkManager.shared.fetchAccounts(), let first = accounts.first {
                subscriberID = first.telephoneno
            }
        }
        
        guard let subID = subscriberID else {
            // Logged in but no accounts found
            let entry = SimpleEntry(date: currentDate, isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: nil)
            return Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(3600)))
        }
        
        // 3. Fetch Data
        do {
            var activeServiceID = subID
            if let serviceDetail = try? await NetworkManager.shared.fetchServiceDetails(telephoneNo: subID),
               let bbService = serviceDetail.listofBBService.first {
                activeServiceID = bbService.serviceID
            }

            async let summary = NetworkManager.shared.fetchUsageSummary(subscriberID: activeServiceID)
            async let vas = NetworkManager.shared.fetchVASBundles(subscriberID: activeServiceID)
            
            let (usageSummary, vasBundles) = try await (summary, vas)
            
            let entry = SimpleEntry(date: currentDate, isLoggedIn: true, usageSummary: usageSummary, vasBundles: vasBundles, subscriberID: subID)
            
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
            return Timeline(entries: [entry], policy: .after(refreshDate))
            
        } catch {
            print("Widget Fetch Error: \(error)")
             let entry = SimpleEntry(date: currentDate, isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: subID, error: error.localizedDescription)
            return Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(900)))
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let isLoggedIn: Bool
    let usageSummary: UsageSummaryBundle?
    let vasBundles: [UsageDetail]
    let subscriberID: String?
    var error: String? = nil
}

struct LegacyProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: "0000000000")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: "0112223333")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        Task {
            let currentDate = Date()
            
            // 1. Check Login
            guard let _ = NetworkManager.shared.accessToken else {
                 let entry = SimpleEntry(date: currentDate, isLoggedIn: false, usageSummary: nil, vasBundles: [], subscriberID: nil)
                 let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(3600)))
                 completion(timeline)
                 return
            }
            
            // 2. Determine Subscriber ID (Default to first)
            var subscriberID: String?
            if let accounts = try? await NetworkManager.shared.fetchAccounts(), let first = accounts.first {
                subscriberID = first.telephoneno
            }
            
            guard let subID = subscriberID else {
                let entry = SimpleEntry(date: currentDate, isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: nil)
                let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(3600)))
                completion(timeline)
                return
            }
            
            // 3. Fetch Data
            do {
                var activeServiceID = subID
                if let serviceDetail = try? await NetworkManager.shared.fetchServiceDetails(telephoneNo: subID),
                   let bbService = serviceDetail.listofBBService.first {
                    activeServiceID = bbService.serviceID
                }

                async let summary = NetworkManager.shared.fetchUsageSummary(subscriberID: activeServiceID)
                async let vas = NetworkManager.shared.fetchVASBundles(subscriberID: activeServiceID)
                
                let (usageSummary, vasBundles) = try await (summary, vas)
                
                let entry = SimpleEntry(date: currentDate, isLoggedIn: true, usageSummary: usageSummary, vasBundles: vasBundles, subscriberID: subID)
                
                let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
                completion(timeline)
                
            } catch {
                print("Legacy Widget Fetch Error: \(error)")
                let entry = SimpleEntry(date: currentDate, isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: subID, error: error.localizedDescription)
                let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(900)))
                completion(timeline)
            }
        }
    }
}

struct SLT_Usage_Meter_WidgetEntryView : View {
    var entry: SimpleEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack {
            if !entry.isLoggedIn {
                LoginPromptView()
            } else if let subID = entry.subscriberID {
                 UsageView(entry: entry, subscriberID: subID)
                    .widgetURL(URL(string: "sltusage://account/\(subID)"))
            } else {
                Text("No accounts found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct LoginPromptView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Please Login")
                .font(.headline)
            Text("Open the app to log in.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .widgetBackground(Color.gray.opacity(0.1))
    }
}

struct UsageView: View {
    let entry: SimpleEntry
    let subscriberID: String
    
    @AppStorage("hidePhoneNumberInWidget", store: UserDefaults(suiteName: "group.com.prabch.sltusage"))
    private var hidePhoneNumberInWidget: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(hidePhoneNumberInWidget ? "Usage Meter for SLT" : subscriberID)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                if let summary = entry.usageSummary {
                    Text(summary.status)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(summary.statusColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            
            // Usage Bars
            if let summary = entry.usageSummary {
                let hasNoAddons = summary.bonusDataSummary == nil && summary.extraGbDataSummary == nil && entry.vasBundles.isEmpty
                let mainUsage = summary.myPackageInfo?.usageDetails.first
                
                if hasNoAddons, let usage = mainUsage, usage.limit == nil {
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usage.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(usage.used)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text(usage.volumeUnit)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Main Package
                    if let packageInfo = summary.myPackageInfo {
                        ForEach(packageInfo.usageDetails.prefix(2)) { usage in
                            WidgetProgressBar(name: usage.name, used: usage.used, limit: usage.limit, unit: usage.volumeUnit, color: .blue)
                        }
                    }
                    
                    // Data Packs
                    if let bonus = summary.bonusDataSummary {
                        WidgetProgressBar(name: "Bonus Data", used: bonus.used, limit: bonus.limit, unit: bonus.volumeUnit, color: .purple)
                    }
                    if let extra = summary.extraGbDataSummary {
                        WidgetProgressBar(name: "Extra GB", used: extra.used, limit: extra.limit, unit: extra.volumeUnit, color: .orange)
                     }
                    
                    // VAS Bundles
                    ForEach(entry.vasBundles.prefix(3)) { bundle in
                        WidgetProgressBar(name: bundle.name, used: bundle.used, limit: bundle.limit, unit: bundle.volumeUnit, color: .green)
                    }
                    
                    if entry.vasBundles.isEmpty && summary.myPackageInfo == nil && summary.bonusDataSummary == nil && summary.extraGbDataSummary == nil {
                         Text("No usage info")
                             .font(.caption)
                             .foregroundColor(.secondary)
                    }
                }
                
            } else {
                if let error = entry.error {
                    Text(error)
                        .font(.system(size: 8))
                        .foregroundColor(.red)
                        .lineLimit(2)
                } else {
                    Text("Loading...")
                        .font(.caption)
                }
            }
            
            Spacer()
        }
        .widgetBackground(Color.gray.opacity(0.1))
    }
}

struct WidgetProgressBar: View {
    let name: String
    let used: String
    let limit: String?
    let unit: String
    let color: Color
    
    @AppStorage("invertProgressBar", store: UserDefaults(suiteName: "group.com.prabch.sltusage"))
    private var invertProgressBar: Bool = false
    
    var progress: Double {
        guard let limitStr = limit, let limitVal = Double(limitStr), limitVal > 0, let usedVal = Double(used) else { return 0 }
        return min(1.0, usedVal / limitVal)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if let limit = limit {
                    if invertProgressBar, let limitVal = Double(limit), let usedVal = Double(used) {
                        let remaining = max(0, limitVal - usedVal)
                        let remainingStr = String(format: "%.1f", remaining).formattedVolume()
                        Text("\(remainingStr) / \(limit.formattedVolume()) \(unit)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(used.formattedVolume()) / \(limit.formattedVolume()) \(unit)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                     Text("\(used.formattedVolume()) \(unit)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    
                    if limit != nil {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * (invertProgressBar ? (1.0 - progress) : progress))
                    } else {
                         Capsule()
                            .fill(color.opacity(0.5))
                    }
                }
            }
            .frame(height: 4)
        }
    }
}

struct SLT_Usage_Meter_Widget: Widget {
    let kind: String = "SLT_Usage_Meter_Widget"

    var body: some WidgetConfiguration {
        if #available(iOS 17.0, macOS 14.0, *) {
            return AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
                SLT_Usage_Meter_WidgetEntryView(entry: entry)
            }
            .configurationDisplayName("Usage Widget")
            .description("Select an account to view data usage")
            .supportedFamilies([.systemSmall, .systemMedium])
        } else {
            return StaticConfiguration(kind: kind, provider: LegacyProvider()) { entry in
                SLT_Usage_Meter_WidgetEntryView(entry: entry)
            }
            .configurationDisplayName("Usage Widget")
            .description("Select an account to view data usage")
            .supportedFamilies([.systemSmall, .systemMedium])
        }
    }
}

extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return self.containerBackground(for: .widget) { backgroundView }
        } else {
            return self.background(backgroundView)
        }
        #else
        if #available(macOS 14.0, *) {
            return self.containerBackground(for: .widget) { backgroundView }
        } else {
            return self.background(backgroundView)
        }
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct Widget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SLT_Usage_Meter_WidgetEntryView(entry: SimpleEntry(date: .now, isLoggedIn: false, usageSummary: nil, vasBundles: [], subscriberID: nil))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            SLT_Usage_Meter_WidgetEntryView(entry: SimpleEntry(date: .now, isLoggedIn: true, usageSummary: nil, vasBundles: [], subscriberID: "0112223333"))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}

// MARK: - Data Models & Networking

// Models and Networking have been moved to shared files
// DataManager removed in favor of NetworkManager


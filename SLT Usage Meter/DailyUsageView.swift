//
//  DailyUsageView.swift
//  SLT Usage Meter
//
//  Created by Danuja on 2026-06-10.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum DailyUsagePlatform {
    static var contentMaxWidth: CGFloat? {
        #if os(macOS)
        return 720
        #else
        return nil
        #endif
    }
    
    static var horizontalPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 0
        #endif
    }
    
    static var sectionSpacing: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 20
        #endif
    }
    
    static var cardBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color.primary.opacity(0.05)
        #endif
    }
    
    static var groupedBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.clear
        #endif
    }
}

struct DailyUsageView: View {
    let subscriberID: String?
    
    /// 0 = current billing period, 1+ = previous months via monthIndex
    @State private var selectedMonthIndex: Int = 0
    @State private var dailyUsage: DailyUsageDataBundle?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var monthLabels: [Int: String] = [:]
    @State private var fetchGeneration = 0
    @State private var oldestEmptyIndex: Int?
    @State private var visibleUpToMonthIndex: Int = 2
    
    private let monthsPerPage = 3
    
    private var sortedDays: [DailyUsageEntry] {
        dailyUsage?.dailylist.sorted { $0.date > $1.date } ?? []
    }
    
    private var totalUsage: Double {
        sortedDays.compactMap { Double($0.daily_total_usage) }.reduce(0, +)
    }
    
    private var averageUsage: Double {
        guard !sortedDays.isEmpty else { return 0 }
        return totalUsage / Double(sortedDays.count)
    }
    
    private var peakDay: DailyUsageEntry? {
        sortedDays.max { (Double($0.daily_total_usage) ?? 0) < (Double($1.daily_total_usage) ?? 0) }
    }
    
    private var volumeUnit: String {
        sortedDays.first?.volumeunit ?? "GB"
    }
    
    private var canShowOlderChip: Bool {
        if let empty = oldestEmptyIndex {
            return visibleUpToMonthIndex < empty - 1
        }
        return true
    }
    
    private var visibleMonthIndices: [Int] {
        let upperBound = oldestEmptyIndex.map { $0 - 1 } ?? visibleUpToMonthIndex
        guard upperBound >= 1 else { return [] }
        return Array(1...min(visibleUpToMonthIndex, upperBound)).filter { index in
            if index <= 2 {
                return monthLabels[index] != nil
            }
            return displayLabel(for: index) != "..."
        }
    }
    
    private var selectedMonthTitle: String {
        if selectedMonthIndex == 0 { return "Current" }
        return displayLabel(for: selectedMonthIndex)
    }
    
    var body: some View {
        Group {
            if subscriberID == nil {
                VStack {
                    Spacer()
                    Text("Select an account to view daily usage")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: DailyUsagePlatform.sectionSpacing) {
                        monthPicker
                            .padding(.top, 8)
                        
                        if let error = errorMessage {
                            errorBanner(error)
                        }
                        
                        if isLoading {
                            DailyUsageSkeletonView()
                        } else if let data = dailyUsage, !data.dailylist.isEmpty {
                            DailyUsageOverviewCard(
                                totalUsage: totalUsage,
                                averageUsage: averageUsage,
                                peakDay: peakDay,
                                dayCount: sortedDays.count,
                                unit: volumeUnit,
                                monthTitle: selectedMonthTitle
                            )
                            
                            dailyBreakdownSection
                        } else if dailyUsage != nil {
                            Text("No daily usage data for \(selectedMonthTitle)")
                                .foregroundColor(.secondary)
                                .padding(.top, 50)
                        }
                    }
                    .padding(.vertical)
                    .frame(maxWidth: DailyUsagePlatform.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, DailyUsagePlatform.horizontalPadding)
                }
                #if os(iOS)
                .refreshable {
                    await refreshDailyUsage()
                }
                #endif
                #if os(macOS)
                .background(DailyUsagePlatform.groupedBackground)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: fetchDailyUsage) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
                #endif
            }
        }
        .onAppear {
            if dailyUsage == nil && !isLoading {
                fetchDailyUsage()
            }
        }
        .onChange(of: subscriberID) { _ in
            resetAndFetch()
        }
    }
    
    @ViewBuilder
    private var dailyBreakdownSection: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Breakdown")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 0) {
                ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
                    DailyUsageRow(day: day, subscriberID: subscriberID ?? "")
                    
                    if index < sortedDays.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DailyUsagePlatform.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        #else
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Breakdown")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ForEach(sortedDays) { day in
                DailyUsageRow(day: day, subscriberID: subscriberID ?? "")
            }
        }
        #endif
    }
    
    @ViewBuilder
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Button("Retry") {
                fetchDailyUsage()
            }
            #if os(macOS)
            .buttonStyle(.bordered)
            #else
            .font(.subheadline)
            #endif
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        #if os(iOS)
        .padding(.horizontal)
        #endif
    }
    
    private var monthPicker: some View {
        #if os(macOS)
        macMonthPicker
        #else
        iosMonthPicker
        #endif
    }
    
    private var iosMonthPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                monthChipRow(scrollProxy: proxy)
                    .padding(.horizontal)
            }
        }
    }
    
    private var macMonthPicker: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    monthChipRow(scrollProxy: proxy)
                }
                .hideHorizontalScrollIndicators()
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private func monthChipRow(scrollProxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            MonthChip(
                title: "Current",
                isSelected: selectedMonthIndex == 0,
                action: { selectMonth(0) }
            )
            .id("month-chip-0")
            
            ForEach(visibleMonthIndices, id: \.self) { index in
                MonthChip(
                    title: displayLabel(for: index),
                    isSelected: selectedMonthIndex == index,
                    action: { selectMonth(index) }
                )
                .id("month-chip-\(index)")
            }
            
            if canShowOlderChip {
                MonthChip(
                    title: "Older",
                    systemImage: "chevron.right",
                    isSelected: false,
                    action: { expandOlderMonths(scrollProxy: scrollProxy) }
                )
                .id("older-chip")
            }
        }
    }
    
    private func expandOlderMonths(scrollProxy: ScrollViewProxy) {
        visibleUpToMonthIndex += monthsPerPage
        withAnimation {
            scrollProxy.scrollTo("older-chip", anchor: .trailing)
        }
    }
    
    private func displayLabel(for index: Int) -> String {
        if let cached = monthLabels[index] {
            return cached
        }
        
        for anchorIndex in stride(from: min(index, visibleUpToMonthIndex), through: 1, by: -1) {
            if let anchorLabel = monthLabels[anchorIndex] {
                return subtractMonths(from: anchorLabel, count: index - anchorIndex)
            }
        }
        
        return "..."
    }
    
    private func subtractMonths(from label: String, count: Int) -> String {
        guard count > 0 else { return label }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        guard let date = formatter.date(from: label),
              let newDate = Calendar.current.date(byAdding: .month, value: -count, to: date) else {
            return label
        }
        return formatter.string(from: newDate)
    }
    
    private func selectMonth(_ index: Int) {
        guard index >= 0, index != selectedMonthIndex else { return }
        selectedMonthIndex = index
        errorMessage = nil
        fetchDailyUsage()
    }
    
    private func resetAndFetch() {
        selectedMonthIndex = 0
        visibleUpToMonthIndex = 2
        dailyUsage = nil
        monthLabels = [:]
        oldestEmptyIndex = nil
        errorMessage = nil
        fetchDailyUsage()
    }
    
    private func formatMonthLabel(_ raw: String) -> String {
        guard raw.count >= 7 else { return raw }
        let month = String(raw.prefix(3))
        let year = String(raw.suffix(4))
        return "\(month) \(year)"
    }
    
    private func labelFromDailyList(_ entries: [DailyUsageEntry]) -> String? {
        guard let dateString = entries.map(\.date).sorted().first else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return nil }
        
        let display = DateFormatter()
        display.dateFormat = "MMM yyyy"
        return display.string(from: date)
    }
    
    private func cacheMonthLabels(from bundle: DailyUsageDataBundle, for index: Int) {
        if index == 0, let months = bundle.previousmonths {
            monthLabels[1] = formatMonthLabel(months.previous1)
            monthLabels[2] = formatMonthLabel(months.previous2)
        }
        if let derived = labelFromDailyList(bundle.dailylist) {
            monthLabels[index] = derived
        }
    }
    
    // MARK: - Fetching
    
    private func fetchDailyUsage() {
        guard let subscriberID else { return }
        
        fetchGeneration += 1
        let generation = fetchGeneration
        let monthIndex = selectedMonthIndex
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let bundle: DailyUsageDataBundle?
                if monthIndex == 0 {
                    bundle = try await NetworkManager.shared.fetchCurrentDailyUsage(subscriberID: subscriberID)
                } else {
                    bundle = try await NetworkManager.shared.fetchPreviousDailyUsage(
                        subscriberID: subscriberID,
                        monthIndex: monthIndex
                    )
                }
                
                DispatchQueue.main.async {
                    guard generation == self.fetchGeneration, monthIndex == self.selectedMonthIndex else { return }
                    
                    if let bundle {
                        self.cacheMonthLabels(from: bundle, for: monthIndex)
                        if bundle.dailylist.isEmpty {
                            self.oldestEmptyIndex = monthIndex
                        }
                        self.dailyUsage = bundle
                    } else {
                        self.oldestEmptyIndex = monthIndex
                        self.dailyUsage = DailyUsageDataBundle(
                            previousmonths: nil,
                            dailylist: []
                        )
                    }
                    
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.fetchGeneration, monthIndex == self.selectedMonthIndex else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func refreshDailyUsage() async {
        await withCheckedContinuation { continuation in
            fetchDailyUsage()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Skeleton

struct DailyUsageSkeletonView: View {
    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 120)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 12) {
                #if os(iOS)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 140, height: 20)
                    .padding(.horizontal)
                    .shimmer()
                #endif
                
                ForEach(0..<6, id: \.self) { _ in
                    DailyUsageRowSkeleton()
                }
            }
        }
        #if os(iOS)
        .padding(.horizontal, 0)
        #endif
    }
}

struct DailyUsageRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 56, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 14)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        #if os(iOS)
        .padding(.horizontal)
        #endif
        .shimmer()
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: geo.size.width * phase)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
    
    @ViewBuilder
    func hideHorizontalScrollIndicators() -> some View {
        if #available(macOS 13.3, iOS 16.4, *) {
            self.scrollIndicators(.hidden, axes: .horizontal)
        } else {
            self
        }
    }
}

// MARK: - Components

struct CapsuleProgressBar: View {
    let percentage: Double
    var height: CGFloat = 8
    var colors: [Color] = [.blue, .cyan]
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: height)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: colors),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1.0, percentage / 100), height: height)
            }
        }
        .frame(height: height)
    }
}

struct MonthChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        #if os(macOS)
        Group {
            if isSelected {
                macChipButton
                    .buttonStyle(.borderedProminent)
            } else {
                macChipButton
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        #else
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        #endif
    }
    
    #if os(macOS)
    private var macChipButton: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
            }
        }
    }
    #endif
}

struct DailyUsageOverviewCard: View {
    let totalUsage: Double
    let averageUsage: Double
    let peakDay: DailyUsageEntry?
    let dayCount: Int
    let unit: String
    var monthTitle: String = "Current"
    
    var body: some View {
        #if os(macOS)
        macOverviewCard
        #else
        iosOverviewCard
        #endif
    }
    
    private var macOverviewCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f %@", totalUsage, unit))
                        .font(.system(size: 28, weight: .semibold))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding()
            
            Divider()
            
            HStack(spacing: 0) {
                overviewStat(label: "Days", value: "\(dayCount)")
                Divider().frame(height: 36)
                overviewStat(label: "Daily Avg", value: String(format: "%.1f %@", averageUsage, unit))
                if let peak = peakDay {
                    Divider().frame(height: 36)
                    overviewStat(label: "Peak", value: peak.displaydate)
                }
            }
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DailyUsagePlatform.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var iosOverviewCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(String(format: "%.1f %@", totalUsage, unit))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Divider()
                .background(Color.white.opacity(0.3))
            
            HStack {
                StatItem(label: "Days", value: "\(dayCount)")
                Spacer()
                StatItem(label: "Daily Avg", value: String(format: "%.1f %@", averageUsage, unit))
                Spacer()
                if let peak = peakDay {
                    StatItem(label: "Peak", value: peak.displaydate)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue, .cyan]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
    
    private func overviewStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

struct DailyUsageRow: View {
    let day: DailyUsageEntry
    let subscriberID: String
    
    @State private var isExpanded = false
    @State private var protocolReport: ProtocolReportBundle?
    @State private var isLoadingReport = false
    @State private var reportError: String?
    @State private var selectedBreakdown = 0
    #if os(macOS)
    @State private var isHovered = false
    #endif
    
    private var usageColor: Color {
        if day.daily_percentage >= 90 { return .red }
        if day.daily_percentage >= 70 { return .orange }
        return .blue
    }
    
    private var canExpand: Bool {
        (Double(day.daily_total_usage) ?? 0) > 0
    }
    
    private var activeEntries: [ProtocolReportEntry] {
        guard let report = protocolReport else { return [] }
        switch selectedBreakdown {
        case 1: return report.download
        case 2: return report.upload
        default: return report.total
        }
    }
    
    var body: some View {
        #if os(macOS)
        macRow
        #else
        iosRow
        #endif
    }
    
    private var dayHeader: some View {
        HStack {
            Text(day.displaydate)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text("\(day.daily_total_usage) \(day.volumeunit)")
                .font(.caption)
                .foregroundColor(.secondary)
            #if os(iOS)
            if canExpand {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            #endif
        }
    }
    
    private var usageBar: some View {
        CapsuleProgressBar(
            percentage: day.daily_percentage,
            height: usageBarHeight,
            colors: [usageColor, usageColor.opacity(0.7)]
        )
    }
    
    private var usageBarHeight: CGFloat {
        #if os(macOS)
        return 6
        #else
        return 8
        #endif
    }
    
    #if os(macOS)
    private var macRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(day.displaydate)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer(minLength: 8)
                        
                        Text("\(day.daily_total_usage) \(day.volumeunit)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    usageBar
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            .onHover { hovering in
                isHovered = hovering
                if hovering && canExpand {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .background(macRowBackground)
            
            if isExpanded {
                protocolDetailsSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
    
    private var macRowBackground: some View {
        Group {
            if isExpanded {
                Color.accentColor.opacity(0.07)
            } else if isHovered && canExpand {
                Color.primary.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }
    #endif
    
    private var iosRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                dayHeader
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            
            usageBar
            
            if isExpanded {
                protocolDetailsSection
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(DailyUsagePlatform.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var protocolDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(iOS)
            Divider()
            #endif
            
            if isLoadingReport {
                ProtocolReportSkeletonView()
            } else if let error = reportError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if protocolReport != nil {
                Picker("Breakdown", selection: $selectedBreakdown) {
                    Text("Total").tag(0)
                    Text("Download").tag(1)
                    Text("Upload").tag(2)
                }
                #if os(macOS)
                .pickerStyle(.segmented)
                .labelsHidden()
                #else
                .pickerStyle(.segmented)
                #endif
                
                if activeEntries.isEmpty {
                    Text("No protocol data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    #if os(macOS)
                    VStack(spacing: 0) {
                        ForEach(Array(activeEntries.enumerated()), id: \.element.id) { index, entry in
                            ProtocolReportRow(entry: entry)
                                .padding(.vertical, 6)
                            
                            if index < activeEntries.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(NSColor.windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    #else
                    ForEach(activeEntries) { entry in
                        ProtocolReportRow(entry: entry)
                    }
                    #endif
                }
            }
        }
        #if os(iOS)
        .padding(.top, 4)
        #endif
    }
    
    private func toggleExpanded() {
        guard canExpand else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        if isExpanded {
            loadProtocolReportIfNeeded()
        }
    }
    
    private func loadProtocolReportIfNeeded() {
        guard protocolReport == nil, !isLoadingReport else { return }
        fetchProtocolReport()
    }
    
    private func fetchProtocolReport() {
        guard !subscriberID.isEmpty else { return }
        
        isLoadingReport = true
        reportError = nil
        
        Task {
            do {
                let report = try await NetworkManager.shared.fetchProtocolReport(
                    subscriberID: subscriberID,
                    date: day.date
                )
                DispatchQueue.main.async {
                    self.protocolReport = report
                    self.isLoadingReport = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.reportError = error.localizedDescription
                    self.isLoadingReport = false
                }
            }
        }
    }
}

struct ProtocolReportRow: View {
    let entry: ProtocolReportEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1f%%", entry.presentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            CapsuleProgressBar(
                percentage: entry.presentage,
                height: 4,
                colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.6)]
            )
        }
    }
}

struct ProtocolReportSkeletonView: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 32)
                .shimmer()
            
            ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 100, height: 12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 36, height: 12)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 4)
                }
                .shimmer()
            }
        }
    }
}

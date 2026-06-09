//
//  DailyUsageView.swift
//  SLT Usage Meter
//
//  Created by Danuja on 2026-06-10.
//

import SwiftUI

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
                    VStack(spacing: 20) {
                        monthPicker
                            .padding(.top)
                        
                        if let error = errorMessage {
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
                                .font(.subheadline)
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                            .padding(.horizontal)
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
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Daily Breakdown")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                                
                                ForEach(sortedDays) { day in
                                    DailyUsageRow(day: day, subscriberID: subscriberID ?? "")
                                }
                            }
                        } else if dailyUsage != nil {
                            Text("No daily usage data for \(selectedMonthTitle)")
                                .foregroundColor(.secondary)
                                .padding(.top, 50)
                        }
                    }
                    .padding(.vertical)
                }
                #if os(iOS)
                .refreshable {
                    await refreshDailyUsage()
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
    
    private var monthPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
                            action: { expandOlderMonths(scrollProxy: proxy) }
                        )
                        .id("older-chip")
                    }
                }
                .padding(.horizontal)
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
                
                await MainActor.run {
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
                await MainActor.run {
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 140)
                .padding(.horizontal)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 140, height: 20)
                    .padding(.horizontal)
                    .shimmer()
                
                ForEach(0..<6, id: \.self) { _ in
                    DailyUsageRowSkeleton()
                }
            }
        }
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
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 120, height: 10)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.08), lineWidth: 1))
        .padding(.horizontal)
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
}

// MARK: - Components

struct MonthChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
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
    }
}

struct DailyUsageOverviewCard: View {
    let totalUsage: Double
    let averageUsage: Double
    let peakDay: DailyUsageEntry?
    let dayCount: Int
    let unit: String
    var monthTitle: String = "Current"
    
    var body: some View {
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
                    StatItem(label: "Peak", value: "\(peak.displaydate)")
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
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                HStack {
                    Text(day.displaydate)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(day.daily_total_usage) \(day.volumeunit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if canExpand {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [usageColor, usageColor.opacity(0.7)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(1.0, day.daily_percentage / 100), height: 8)
                }
            }
            .frame(height: 8)
            
            if isExpanded {
                protocolDetailsSection
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var protocolDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            
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
                .pickerStyle(.segmented)
                
                if activeEntries.isEmpty {
                    Text("No protocol data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(activeEntries) { entry in
                        ProtocolReportRow(entry: entry)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
    
    private func toggleExpanded() {
        guard canExpand else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        if isExpanded && protocolReport == nil && !isLoadingReport {
            fetchProtocolReport()
        }
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
                await MainActor.run {
                    self.protocolReport = report
                    self.isLoadingReport = false
                }
            } catch {
                await MainActor.run {
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
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: geo.size.width * min(1.0, entry.presentage / 100), height: 4)
                }
            }
            .frame(height: 4)
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

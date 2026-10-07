import AppKit
import Charts
import SwiftUI

struct AILimitsWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AILimitsCompactView(item: item))
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AILimitsPopoutView(store: store, item: item, profileID: profileID))
    }
}

struct AIActivityWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AIActivityCompactView(item: item))
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AIActivityPopoutView(store: store, item: item, profileID: profileID))
    }
}

enum AILimitsStalePresentation {
    /// A retained reading keeps its original success time and is never presented as current.
    static func message(updatedAt: Date?, error: String) -> String {
        "Stale · last successful reading" + (updatedAt.map { " " + $0.formatted(date: .abbreviated, time: .shortened) } ?? " time unknown")
            + ". Refresh failed: " + error
    }
}

enum AIFacePresentation {
    static func selectedProvider(configuration: WidgetConfiguration) -> AIProvider? {
        if configuration.aiLimitsVisibleProviders.contains(configuration.aiLimitsCompactProvider) { return configuration.aiLimitsCompactProvider }
        return configuration.aiLimitsProviderOrder.first(where: configuration.aiLimitsVisibleProviders.contains)
    }
    /// Thresholds always refer to used capacity, even when the user displays remaining capacity.
    static func limitColor(usedPercent: Int?) -> Color {
        guard let usedPercent else { return .secondary }
        return usedPercent >= 100 ? WidgetPalette.critical : usedPercent >= 90 ? WidgetPalette.warning : .secondary
    }
    static func limitHeroColor(usedPercent: Int?) -> Color {
        guard let usedPercent, usedPercent >= 90 else { return .primary }
        return limitColor(usedPercent: usedPercent)
    }
    static func primaryReading(configuration: WidgetConfiguration) -> AIProviderLimitReading? {
        selectedProvider(configuration: configuration).flatMap { configuration.aiLimitsSnapshot?.reading(for: $0) }
    }
    static func narrowActivityValue(snapshot: AIActivitySnapshot?, locale: Locale = .current) -> String {
        guard let snapshot, snapshot.available else { return activityValue(snapshot: snapshot) }
        let tokens = Double(snapshot.totals.totalTokens)
        let scale: Double = tokens >= 1_000_000_000 ? 1_000_000_000 : tokens >= 1_000_000 ? 1_000_000 : tokens >= 1_000 ? 1_000 : 1
        let suffix = scale == 1_000_000_000 ? "B" : scale == 1_000_000 ? "M" : scale == 1_000 ? "K" : ""
        return (tokens / scale).formatted(.number.precision(.fractionLength(0)).locale(locale)) + suffix
            + (snapshot.partial && !snapshot.estimated ? "+" : "")
    }
    static func activityValue(snapshot: AIActivitySnapshot?) -> String {
        guard let snapshot, snapshot.available else { return snapshot == nil ? "Set up" : "No data" }
        return AIActivityFormatting.tokens(snapshot.totals.totalTokens) + (snapshot.partial && !snapshot.estimated ? "+" : "")
    }
    static func limitValue(reading: AIProviderLimitReading?, mode: AIUsageRepresentation) -> String {
        guard let reading else { return "Set up" }
        return compactPercent(reading.windows.first, mode: mode)
    }
}

struct AILimitsCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var selectedProvider: AIProvider? { AIFacePresentation.selectedProvider(configuration: configuration) }
    private var reading: AIProviderLimitReading? { selectedProvider.flatMap { configuration.aiLimitsSnapshot?.reading(for: $0) } }
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetLayout) private var layout
    @Environment(\.widgetAccent) private var accent
    var body: some View {
        let window = reading?.windows.first
        let state = AIFacePresentation.limitColor(usedPercent: window?.usedPercent)
        VStack(spacing: 3) {
            ModuleStack(kind: "AI Limits", label: selectedProvider?.shortName ?? "AI Limits",
                        value: AIFacePresentation.limitValue(reading: reading, mode: configuration.aiLimitsRepresentation),
                        unit: window == nil ? "" : configuration.aiLimitsRepresentation == .remaining ? "left" : "used",
                        size: reading == nil ? .small : .medium, valueColor: (window?.usedPercent ?? 0) >= 90 ? state : .primary,
                        trailing: layout == .standard && width > 54 && reading?.lastRefreshError == nil ? window.map(compactWindowTitle) : nil)
            if width > 54, let window,
               let percent = configuration.aiLimitsRepresentation == .remaining ? window.remainingPercent : window.usedPercent {
                UsageBar(fraction: Double(percent) / 100,
                         color: (window.usedPercent ?? 0) >= 90 ? state : WidgetPalette.resolved(kind: "AI Limits", accent: accent))
            }
        }.moduleInsets()
            .help("AI Limits · Open to see provider windows")
            .accessibilityElement(children: .combine)
            .overlay(alignment: .topTrailing) {
                if reading?.lastRefreshError != nil {
                    Image(systemName: "exclamationmark.circle.fill").font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning)
                        .padding(.top, 4).padding(.trailing, 4)
                        .help("Stale: refresh failed, last successful reading shown").accessibilityLabel("Stale: refresh failed, last successful reading shown")
                }
            }
    }
}

enum AILimitsFaceSample {
    static func item() -> DockItem {
        var item = DockItem.widget("AI Limits")
        item.widgetConfiguration?.aiLimitsVisibleProviders = [.claude]
        item.widgetConfiguration?.aiLimitsCompactProvider = .claude
        item.widgetConfiguration?.aiLimitsSnapshot = AILimitsSnapshot(fetchedAt: .now, readings: [
            AIProviderLimitReading(provider: .claude, availability: .available, windows: [
                AILimitWindow(name: "Session", usedPercent: 28, durationMinutes: 300)
            ], updatedAt: .now)
        ])
        return item
    }
}

private struct AILimitsPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private var snapshotRendering: Bool { false }
    #endif
    @State private var isRefreshing = false
    @State private var refreshRequestID = UUID()
    @State private var activeRefreshTask: Task<AILimitsSnapshot, Never>?
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var copiedClaudeStatusLineCommand = false

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var orderedProviders: [AIProvider] {
        var result = configuration.aiLimitsProviderOrder.filter(AIProvider.allCases.contains)
        for provider in AIProvider.allCases where !result.contains(provider) { result.append(provider) }
        return result
    }
    private var limitsRefreshKey: String {
        orderedProviders.filter(configuration.aiLimitsVisibleProviders.contains)
            .map(\.rawValue).joined(separator: ",") + "|\(configuration.aiCopilotMonthlyCreditAllowance ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                if let reading = AIFacePresentation.primaryReading(configuration: configuration) {
                    providerSection(reading, primary: true)
                } else {
                    WidgetPopoutHero(value: "No limits available", caption: "Choose a provider in Settings.", symbol: "gauge.with.dots.needle.0percent")
                }
                let secondary = visibleReadings.filter { $0.provider != AIFacePresentation.selectedProvider(configuration: configuration) }
                if !secondary.isEmpty {
                    GroupedSection("Other providers") {
                        ForEach(secondary) { reading in
                            GroupedRow(reading.provider.title, subtitle: reading.lastRefreshError ?? reading.message,
                                value: AIFacePresentation.limitValue(reading: reading, mode: configuration.aiLimitsRepresentation))
                            ForEach(Array(reading.windows.dropFirst())) { window in
                                limitWindow(window, showsValue: true)
                            }
                        }
                    }
                }
            }
            WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) {
                controls
                ForEach(orderedProviders.filter { configuration.aiLimitsVisibleProviders.contains($0) && ($0 == .codex || $0 == .claude) }) { provider in
                    AIAccountConnectionView(provider: provider, allowsAccountActions: store.allowsSystemChanges,
                                            showsLimitsSetup: true, refresh: { await refresh(force: true) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: limitsRefreshKey) {
            guard !snapshotRendering else { return }
            // Opening the popout loads only a reading older than the update interval.
            await refresh(force: false)
        }
        .onDisappear {
            refreshRequestID = UUID()
            activeRefreshTask?.cancel()
            activeRefreshTask = nil
            isRefreshing = false
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupedSection() {
                GroupedRow("Limit display") {
                    Picker("Limit display", selection: layoutBinding) {
                        ForEach(AILimitLayout.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                GroupedRow("Show") {
                    Picker("Show", selection: representationBinding) {
                        ForEach(AIUsageRepresentation.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                GroupedRow("Dock provider") {
                    Picker("Dock provider", selection: compactProviderBinding) {
                        ForEach(orderedProviders.filter(configuration.aiLimitsVisibleProviders.contains)) { Text($0.title).tag($0) }
                    }.labelsHidden().disabled(configuration.aiLimitsVisibleProviders.isEmpty)
                }
            }
            GroupedSection("Providers", footer: "Provider-reported limits from this Mac.") {
                ForEach(orderedProviders) { provider in
                    GroupedRow(provider.title) {
                        Toggle(provider.title, isOn: visibleBinding(for: provider)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Button { move(provider, offset: -1) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless).disabled(orderedProviders.first == provider).accessibilityLabel("Move \(provider.title) earlier")
                        Button { move(provider, offset: 1) } label: { Image(systemName: "arrow.down") }
                            .buttonStyle(.borderless).disabled(orderedProviders.last == provider).accessibilityLabel("Move \(provider.title) later")
                    }
                    if provider == .copilot, configuration.aiLimitsVisibleProviders.contains(.copilot) {
                        GroupedRow("Monthly AI-credit allowance") {
                            TextField("Credits", value: copilotAllowanceBinding, format: .number)
                                .textFieldStyle(.plain).frame(width: 86).multilineTextAlignment(.trailing)
                        }
                        GroupedRow("Quick set", subtitle: "Match your personal GitHub plan. Copilot usage resets monthly.") {
                            HStack(spacing: 5) {
                                allowancePreset("Pro", credits: 1_500)
                                allowancePreset("Pro+", credits: 7_000)
                                allowancePreset("Max", credits: 20_000)
                            }
                        }
                    }
                }
            }
        }
        .help("A dash means unavailable. MyDock reads local provider APIs without starting a task, inferring percentages or spending model tokens.")
    }

    private var visibleReadings: [AIProviderLimitReading] {
        orderedProviders.filter(configuration.aiLimitsVisibleProviders.contains).compactMap { provider in
            configuration.aiLimitsSnapshot?.reading(for: provider)
        }
    }

    @ViewBuilder
    private func providerSection(_ reading: AIProviderLimitReading, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetPopoutHero(value: AIFacePresentation.limitValue(reading: reading, mode: configuration.aiLimitsRepresentation),
                caption: reading.provider.title + (reading.plan.map { " · " + $0.capitalized } ?? "") + " · " + configuration.aiLimitsRepresentation.title,
                valueColor: AIFacePresentation.limitHeroColor(usedPercent: reading.windows.first?.usedPercent))
            if let error = reading.lastRefreshError {
                Label("Saved limits; " + error, systemImage: "exclamationmark.triangle")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let identity = reading.verifiedAccountIdentity {
                Text("Verified account: " + identity).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
            }
            if reading.windows.isEmpty, let message = reading.message {
                Text(message).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !reading.windows.isEmpty {
                GroupedSection {
                    ForEach(Array(reading.windows.enumerated()), id: \.element.id) { index, window in
                        limitWindow(window, showsValue: !primary || index != 0)
                    }
                }
            }
            if reading.availability != .available, reading.provider != .claude, reading.provider != .codex {
                Text("Open " + reading.provider.title + " to set up local readings.")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    .help(reading.provider.setupInstructions)
                if let command = reading.provider.statusLineSetupCommand {
                    HStack {
                        Button("Copy Status Line Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            copiedClaudeStatusLineCommand = true
                        }
                        if copiedClaudeStatusLineCommand {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        if let url = URL(string: "https://code.claude.com/docs/en/statusline") {
                            Link("Status line docs", destination: url)
                        }
                    }
                    .font(DockDesign.Grouped.subtitleFont)
                    Text("Merge with any existing statusLine command.")
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                        .help("Merge this file-writing step into the existing Claude Code statusLine command to preserve its terminal display.")
                }
            }
        }

    }

    private func limitWindow(_ window: AILimitWindow, showsValue: Bool) -> some View {
        let percent = configuration.aiLimitsRepresentation == .remaining ? window.remainingPercent : window.usedPercent
        return GroupedRow(window.name, subtitle: window.resetsAt.map { "Resets " + $0.formatted(.relative(presentation: .numeric)) }) {
            if showsValue { Text(percent.map { "\($0)%" } ?? "—").monospacedDigit() }
            if let percent, configuration.aiLimitsLayout == .bars {
                ProgressView(value: Double(min(100, max(0, percent))), total: 100)
                    .tint(AIFacePresentation.limitColor(usedPercent: window.usedPercent)).frame(width: 80)
            } else if let percent, configuration.aiLimitsLayout == .rings {
                ModuleRing(fraction: Double(min(100, max(0, percent))) / 100,
                           color: AIFacePresentation.limitColor(usedPercent: window.usedPercent)) {
                    EmptyView()
                }.frame(width: 28, height: 28)
            }
        }
    }

    private var layoutBinding: Binding<AILimitLayout> {
        Binding(get: { configuration.aiLimitsLayout }, set: { value in update { $0.aiLimitsLayout = value } })
    }
    private var representationBinding: Binding<AIUsageRepresentation> {
        Binding(get: { configuration.aiLimitsRepresentation }, set: { value in update { $0.aiLimitsRepresentation = value } })
    }
    private var compactProviderBinding: Binding<AIProvider> {
        Binding(get: { configuration.aiLimitsCompactProvider }, set: { value in update { $0.aiLimitsCompactProvider = value } })
    }
    private var copilotAllowanceBinding: Binding<Int> {
        Binding(get: { configuration.aiCopilotMonthlyCreditAllowance ?? 0 }, set: { value in
            update { configuration in
                let bounded = min(1_000_000, max(0, value))
                configuration.aiCopilotMonthlyCreditAllowance = bounded == 0 ? nil : bounded
            }
        })
    }
    private func allowancePreset(_ title: String, credits: Int) -> some View {
        Button(title) { update { $0.aiCopilotMonthlyCreditAllowance = credits } }
            .buttonStyle(.borderless)
            .help("Set the monthly allowance to \(credits.formatted()) AI credits")
    }
    private func visibleBinding(for provider: AIProvider) -> Binding<Bool> {
        Binding(get: { configuration.aiLimitsVisibleProviders.contains(provider) }, set: { enabled in
            update { value in
                if enabled, !value.aiLimitsVisibleProviders.contains(provider) { value.aiLimitsVisibleProviders.append(provider) }
                else if !enabled { value.aiLimitsVisibleProviders.removeAll { $0 == provider } }
                if !value.aiLimitsVisibleProviders.contains(value.aiLimitsCompactProvider), let first = value.aiLimitsVisibleProviders.first {
                    value.aiLimitsCompactProvider = first
                }
            }
        })
    }
    private func move(_ provider: AIProvider, offset: Int) {
        update { value in
            var list = value.aiLimitsProviderOrder.filter(AIProvider.allCases.contains)
            for item in AIProvider.allCases where !list.contains(item) { list.append(item) }
            guard let index = list.firstIndex(of: provider) else { return }
            let target = index + offset
            guard list.indices.contains(target) else { return }
            list.swapAt(index, target)
            value.aiLimitsProviderOrder = list
        }
    }
    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }
    private func refresh(force: Bool) async {
        let requestID = UUID()
        refreshRequestID = requestID
        isRefreshing = true
        defer { if refreshRequestID == requestID { isRefreshing = false } }
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID, force: force)
    }
}

struct AIActivityCompactView: View {
    var item: DockItem
    var displayScale: CGFloat = 1
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetLayout) private var layout
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: AIActivitySnapshot? {
        guard let snapshot = configuration.aiActivitySnapshot, snapshot.provider == configuration.aiActivityProvider,
              snapshot.range == configuration.aiActivityRange else { return nil }
        return snapshot
    }
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetShowsLabel) private var showsLabel
    var body: some View {
        let narrow = WidgetModuleMetrics.isNarrow(width)
        HStack(spacing: 10) {
            VStack(alignment: narrow || (!showsLabel && layout != .trend) ? .center : .leading, spacing: 2) {
                ModuleLabel(kind: "AI Activity", text: configuration.aiActivityProvider.shortName,
                    symbol: configuration.aiActivityProvider == .codex ? "terminal" : "sparkle")
                ViewThatFits(in: .horizontal) {
                    if !narrow && layout != .compact, let secondary {
                        (Text(AIFacePresentation.activityValue(snapshot: snapshot)).font(DockDesign.Module.valueMedium)
                         + Text(" · " + secondary).font(DockDesign.Module.label).foregroundColor(.secondary))
                            .lineLimit(1).fixedSize()
                    }
                    ModuleValue(value: AIFacePresentation.activityValue(snapshot: snapshot),
                        unit: snapshot?.available == true && !narrow ? "tokens" : "",
                        size: snapshot?.available == true ? .medium : .small)
                        .fixedSize()
                    ModuleValue(value: AIFacePresentation.narrowActivityValue(snapshot: snapshot),
                        size: snapshot?.available == true ? .medium : .small)
                }
            }.frame(maxWidth: .infinity, alignment: narrow || (!showsLabel && layout != .trend) ? .center : .leading)
            if layout == .trend && !narrow, let snapshot, snapshot.available, snapshot.points.count > 1 {
                MicroSparkline(values: snapshot.points.map { Double($0.totalTokens) }, color: WidgetPalette.resolved(kind: "AI Activity", accent: accent))
                    .frame(width: 46, height: 26)
            }
        }.moduleInsets().frame(height: 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(configuration.aiActivityProvider.title) AI Activity")
            .accessibilityValue(snapshot?.available == true ? snapshot!.tokensText + (secondary.map { ", " + $0 } ?? "") : "No local activity. Open for setup.")
            .help(snapshot.map { "\($0.provider.title) · \($0.tokensText) · \($0.range.activityTitle). Based on available local logs. " + ($0.range == .today ? "Sparkline shows the last 7 days." : "") } ?? "Open to set up local activity")
    }
    private var secondary: String? {
        guard let snapshot, snapshot.available else { return nil }
        switch configuration.aiActivitySecondaryMetric {
        case .sessions: return snapshot.totals.sessions > 0 ? "\(snapshot.totals.sessions.formatted()) \(snapshot.totals.sessions == 1 ? "session" : "sessions")" : nil
        case .toolCalls: return snapshot.totals.toolCalls > 0 ? "\(snapshot.totals.toolCalls.formatted()) \(snapshot.totals.toolCalls == 1 ? "tool" : "tools")" : nil
        case .requests: return snapshot.totals.requests > 0 ? "\(snapshot.totals.requests.formatted()) \(snapshot.totals.requests == 1 ? "request" : "requests")" : nil
        case .none: return nil
        }
    }
}

/// A restrained native identity, without pretending an SF Symbol is a provider logo.
struct AIProviderGlyph: View {
    var provider: AIProvider
    var body: some View {
        Image(systemName: provider == .codex ? "terminal.fill" : provider == .claude ? "sparkle" : "sparkles")
            .resizable().scaledToFit().foregroundStyle(.primary).accessibilityHidden(true)
    }
}

struct AIActivityPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    var accountOverride: AIAccountStatus? = nil
    @State private var account: AIAccountStatus?
    @State private var recoveryMessage: String?

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }
    private var snapshot: AIActivitySnapshot? {
        guard let snapshot = configuration.aiActivitySnapshot, snapshot.provider == configuration.aiActivityProvider,
              snapshot.range == configuration.aiActivityRange else { return nil }
        return snapshot
    }
    private var currentItem: DockItem { var result = item; result.widgetConfiguration = configuration; return result }
    var body: some View {
        AIActivitySummary(store: store, item: currentItem, account: accountOverride ?? account,
                          recoveryMessage: recoveryMessage, refresh: refresh, recover: recover,
                          provider: providerBinding, range: rangeBinding, chartStyle: chartStyleBinding)
            .task(id: "\(configuration.aiActivityProvider.rawValue)|\(configuration.aiActivityRange.rawValue)") {
                guard store.allowsSystemChanges else { return }
                await store.widgetData.refresh(item: currentItem, profileID: profileID, force: false)
            }
            .task(id: "\(configuration.aiActivityProvider.rawValue)|\(snapshot?.available == true)") {
                account = nil
                let provider = configuration.aiActivityProvider
                guard store.allowsSystemChanges, snapshot?.available != true, [.codex, .claude].contains(provider) else { return }
                let worker = Task.detached(priority: .utility) { AIAccountService.detect(provider) }
                let status = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                account = status
            }
    }
    private var providerBinding: Binding<AIProvider> {
        Binding(get: { configuration.aiActivityProvider }, set: { value in
            update { $0.aiActivityProvider = value; $0.aiActivitySnapshot = nil }; account = nil; recoveryMessage = nil
        })
    }
    private var rangeBinding: Binding<AIActivityRange> {
        Binding(get: { configuration.aiActivityRange }, set: { value in update { $0.aiActivityRange = value; $0.aiActivitySnapshot = nil } })
    }
    private var chartStyleBinding: Binding<AIActivityChartStyle> {
        Binding(get: { configuration.aiActivityChartStyle }, set: { value in update { $0.aiActivityChartStyle = value } })
    }
    private func update(_ body: (inout WidgetConfiguration) -> Void) { store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body) }
    private func refresh() { Task { await store.widgetData.refresh(item: currentItem, profileID: profileID) } }
    private func recover() {
        guard store.allowsSystemChanges else { return }
        if configuration.aiActivityProvider == .codex,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
           InstalledAppCatalog.validatedApplication(at: url) != nil { NSWorkspace.shared.open(url) }
        else {
            do { try AIAccountService.signIn(configuration.aiActivityProvider) }
            catch { recoveryMessage = "Open \(configuration.aiActivityProvider.title) and sign in, then refresh." }
        }
    }
}

private struct AIActivitySummary: View {
    @ObservedObject var coordinator: WidgetDataCoordinator
    let item: DockItem
    let account: AIAccountStatus?
    let recoveryMessage: String?
    let refresh: () -> Void
    let recover: () -> Void
    let allowsActions: Bool
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @Binding var provider: AIProvider
    @Binding var range: AIActivityRange
    @Binding var chartStyle: AIActivityChartStyle

    init(store: ProfileStore, item: DockItem, account: AIAccountStatus?, recoveryMessage: String?, refresh: @escaping () -> Void,
         recover: @escaping () -> Void, provider: Binding<AIProvider>, range: Binding<AIActivityRange>, chartStyle: Binding<AIActivityChartStyle>) {
        coordinator = store.widgetData; self.item = item; self.account = account; self.recoveryMessage = recoveryMessage
        self.refresh = refresh; self.recover = recover; allowsActions = store.allowsSystemChanges
        _provider = provider; _range = range; _chartStyle = chartStyle
    }
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: AIActivitySnapshot? {
        guard let s = configuration.aiActivitySnapshot, s.provider == provider, s.range == range else { return nil }
        return s
    }
    private var query: WidgetDataQuery { WidgetDataQuery.make(kind: "AI Activity", configuration: configuration)! }
    private var refreshing: Bool { coordinator.refreshing.contains(query) }
    private var failed: Bool { coordinator.errors[query] != nil || (snapshot?.partial == true && snapshot?.available == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                WidgetFreshnessView(coordinator: coordinator, item: item, refresh: refresh)
                    .buttonStyle(.borderless)
                if let s = snapshot, s.available {
                    metrics(s)
                    if chartStyle != .totals { chart(s) }
                    if s.totals.requests > 0 || s.totals.reportedCostUSD != nil {
                        HStack {
                            if s.totals.requests > 0 { Text("\(s.totals.requests.formatted()) requests") }
                            Spacer()
                            if let cost = s.totals.reportedCostUSD { Text("Reported cost \(cost.formatted(.currency(code: "USD")))") }
                        }.font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                    }
                } else {
                    emptyState
                }
                if let recoveryMessage { Text(recoveryMessage).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary) }
            }
            WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) {
                GroupedSection(footer: provenanceFooter) {
                    GroupedRow("Provider") {
                        Picker("Provider", selection: $provider) {
                            ForEach([AIProvider.codex, .claude, .grok]) { Text($0.title).tag($0) }
                        }.labelsHidden().accessibilityLabel("Activity provider").accessibilityValue(provider.title)
                    }
                    GroupedRow("Activity range") {
                        Picker("Activity range", selection: $range) {
                            ForEach(AIActivityRange.allCases) { Text($0.activityTitle).tag($0) }
                        }.labelsHidden()
                    }
                    GroupedRow("Chart") {
                        Picker("Chart", selection: $chartStyle) { ForEach(AIActivityChartStyle.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                    }
                }.accessibilityLabel("Activity options").help(snapshot?.sourceDescription ?? "Activity is read from local session logs.")
            }

        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var provenanceFooter: String {
        if snapshot?.estimated == true { return "Local log estimate, not a billing total." }
        if snapshot?.partial == true { return "Local log totals may be incomplete." }
        return "Local session logs, not billing totals."
    }
    private func metrics(_ s: AIActivitySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            metric("Tokens", value: AIActivityFormatting.tokens(s.totals.totalTokens) + (s.partial && !s.estimated ? "+" : ""), primary: true)
                .help(s.tokensText + ". " + s.sourceDescription)
            metric("Sessions", value: AIActivityFormatting.tokens(Int64(s.totals.sessions)))
                .help("Distinct local sessions with activity in \(s.range.activityDescription). Daily counts count each session once per day.")
            metric("Tool calls", value: AIActivityFormatting.tokens(Int64(s.totals.toolCalls)))
        }
    }
    private func metric(_ title: String, value: String, primary: Bool = false) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value).font(primary ? DockDesign.Module.valueLarge : DockDesign.Module.valueMedium).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
        }.widgetPopoutHeroAligned().accessibilityElement(children: .combine)
    }
    private func chart(_ s: AIActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Token activity").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(range == .today ? "Last 7 days" : range.activityDescription).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
            }
            Chart(s.points) { point in
                if chartStyle == .bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Tokens", point.totalTokens))
                        .foregroundStyle(Color.secondary).cornerRadius(3)
                } else {
                    LineMark(x: .value("Day", point.date), y: .value("Tokens", point.totalTokens)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round)).interpolationMethod(.linear)
                }
            }
            .chartYScale(domain: 0...max(1, Double(s.points.map(\.totalTokens).max() ?? 0) * 1.12))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 136).accessibilityLabel("\(provider.title) token activity by day, \(range == .today ? "last 7 days" : range.activityDescription)")
        }
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: failed ? "exclamationmark.circle" : "chart.bar.xaxis").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(emptyTitle).font(.system(size: 14, weight: .semibold))
            Text(emptyDetail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let account, account.state != .signedIn, [.codex, .claude].contains(provider), !refreshing {
                Button(provider == .codex ? "Open Codex" : "Open Claude Code", action: recover).controlSize(.small).disabled(!allowsActions)
                    .help("Open your provider to connect, then refresh local activity")
            }
        }.frame(maxWidth: .infinity).frame(minHeight: 176).padding(.horizontal, 22)
    }
    private var emptyTitle: String {
        if refreshing && snapshot == nil { return "Loading activity" }
        if failed { return "Activity unavailable" }
        if let account, account.state != .signedIn { return "\(provider.title) account unavailable" }
        return "No activity yet"
    }
    private var emptyDetail: String {
        if refreshing && snapshot == nil { return "Reading session counters from this Mac." }
        if failed { return "Local records couldn’t be read. Try refreshing." }
        if let account, account.state != .signedIn { return "Open \(provider.title) to connect. Activity will appear here as you use it." }
        if ![AIProvider.codex, .claude, .grok].contains(provider) { return "This provider has no supported local activity source. Choose another provider." }
        return "Use \(provider.title) on this Mac, then refresh to see your local activity."
    }
}

extension AIActivityRange {
    var activityTitle: String {
        switch self { case .today: "Today"; case .sevenDays: "7D"; case .thirtyDays: "30D"; case .monthToDate: "Month" }
    }
    var activityDescription: String {
        switch self { case .today: "Today"; case .sevenDays: "Last 7 days"; case .thirtyDays: "Last 30 days"; case .monthToDate: "This month" }
    }
}

private extension AIProvider {
    var shortName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .geminiCLI: "Gemini"
        case .copilot: "Copilot"
        case .antigravity: "Antigrav."
        }
    }
}

private func limitLabel(_ window: AILimitWindow, mode: AIUsageRepresentation) -> String {
    let value = mode == .remaining ? window.remainingPercent : window.usedPercent
    return value.map { "\($0)% \(mode.title.lowercased())" } ?? "Unavailable"
}

private func compactPercent(_ window: AILimitWindow?, mode: AIUsageRepresentation) -> String {
    guard let window else { return "—" }
    let value = mode == .remaining ? window.remainingPercent : window.usedPercent
    return value.map { "\($0)%" } ?? "—"
}

private func compactWindowTitle(for window: AILimitWindow) -> String {
    guard let minutes = window.durationMinutes else {
        return window.name == "Monthly AI credits" ? "Month" : String(window.name.prefix(6))
    }
    return switch minutes {
    case 300: "5h"
    case 10_080: "7d"
    case let value where value >= 1_440: "\(value / 1_440)d"
    default: "\(minutes)m"
    }
}

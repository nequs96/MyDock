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

private struct AILimitsCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var selectedProvider: AIProvider? {
        if configuration.aiLimitsVisibleProviders.contains(configuration.aiLimitsCompactProvider) {
            return configuration.aiLimitsCompactProvider
        }
        return configuration.aiLimitsProviderOrder.first(where: configuration.aiLimitsVisibleProviders.contains)
    }

    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(kind: "AI Limits", title: selectedProvider?.shortName ?? "AI Limits")
            if let provider = selectedProvider, let window = configuration.aiLimitsSnapshot?.reading(for: provider)?.windows.first {
                MetricText(value: compactPercent(window, mode: configuration.aiLimitsRepresentation), unit: configuration.aiLimitsRepresentation == .remaining ? "left" : "used", size: 19)
                if layout == .standard { Text(window.name).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                if let percent = configuration.aiLimitsRepresentation == .remaining ? window.remainingPercent : window.usedPercent {
                    UsageBar(fraction: Double(percent) / 100, color: WidgetPalette.accent("AI Limits"))
                }
            } else { Text("Set up").font(.system(size: 13, weight: .medium)) }
        }.padding(.horizontal, 9).frame(width: width, height: 54)
            .help("AI Limits · Open to see provider windows")
            .overlay(alignment: .topTrailing) {
                if let provider = selectedProvider, configuration.aiLimitsSnapshot?.reading(for: provider)?.lastRefreshError != nil {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        .help("Stale: refresh failed, last successful reading shown").accessibilityLabel("Stale: refresh failed, last successful reading shown")
                }
            }
    }
}


private struct AILimitsPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var isRefreshing = false
    @State private var refreshRequestID = UUID()
    @State private var activeRefreshTask: Task<AILimitsSnapshot, Never>?
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
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.cyan)
                Text("AI Limits").font(.headline)
                Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(isRefreshing)
                if isRefreshing { ProgressView().controlSize(.small) }
            }

            ForEach(orderedProviders.filter { configuration.aiLimitsVisibleProviders.contains($0) && ($0 == .codex || $0 == .claude) }) { provider in
                AIAccountConnectionView(provider: provider, allowsAccountActions: store.allowsSystemChanges,
                                        showsLimitsSetup: true, refresh: { await refresh() })
            }
            controls
            Divider()
            if visibleReadings.isEmpty {
                Text(configuration.aiLimitsVisibleProviders.isEmpty
                     ? "Turn on a provider to show its usage window here."
                     : "Refreshing provider limits…")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(visibleReadings) { reading in providerSection(reading) }
            }
            if let fetchedAt = configuration.aiLimitsSnapshot?.fetchedAt {
                Label("Last refresh \(fetchedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            DataSourceProvenanceView(provenance: .aiLimits(snapshot: configuration.aiLimitsSnapshot))
            Text("A dash means unavailable. MyDock reads Codex's local app-server rate-limit API without starting a task. It does not infer percentages or refresh limits by spending model tokens.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 375, alignment: .leading)
        .frame(minHeight: 220, alignment: .topLeading)
        .task(id: limitsRefreshKey) {
            await refresh()
        }
        .onDisappear {
            refreshRequestID = UUID()
            activeRefreshTask?.cancel()
            activeRefreshTask = nil
            isRefreshing = false
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Limit display").foregroundStyle(.secondary)
                Picker("Limit display", selection: layoutBinding) {
                    ForEach(AILimitLayout.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
                Spacer()
                Picker("Show", selection: representationBinding) {
                    ForEach(AIUsageRepresentation.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            HStack {
                Text("Dock provider").foregroundStyle(.secondary)
                Picker("Dock provider", selection: compactProviderBinding) {
                    ForEach(orderedProviders.filter(configuration.aiLimitsVisibleProviders.contains)) { Text($0.title).tag($0) }
                }.labelsHidden().disabled(configuration.aiLimitsVisibleProviders.isEmpty)
            }
            Text("Choose popout visibility/order and the provider shown in the compact tile.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(orderedProviders) { provider in
                HStack(spacing: 7) {
                    Toggle(provider.title, isOn: visibleBinding(for: provider)).toggleStyle(.checkbox)
                    Spacer()
                    Button { move(provider, offset: -1) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless).disabled(orderedProviders.first == provider)
                    Button { move(provider, offset: 1) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless).disabled(orderedProviders.last == provider)
                }
                .font(.caption)
                if provider == .copilot, configuration.aiLimitsVisibleProviders.contains(.copilot) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("Monthly AI-credit allowance")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            TextField("Credits", value: copilotAllowanceBinding, format: .number)
                                .textFieldStyle(DockTextFieldStyle())
                                .frame(width: 86)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack(spacing: 5) {
                            Text("Quick set:").foregroundStyle(.tertiary)
                            allowancePreset("Pro", credits: 1_500)
                            allowancePreset("Pro+", credits: 7_000)
                            allowancePreset("Max", credits: 20_000)
                        }
                        Text("Match your personal GitHub plan. Copilot usage resets monthly.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .font(.caption2)
                    .padding(.leading, 20)
                }
            }
        }
        .font(.caption)
    }

    private var visibleReadings: [AIProviderLimitReading] {
        orderedProviders.filter(configuration.aiLimitsVisibleProviders.contains).compactMap { provider in
            configuration.aiLimitsSnapshot?.reading(for: provider)
        }
    }

    @ViewBuilder
    private func providerSection(_ reading: AIProviderLimitReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reading.provider.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let plan = reading.plan { Text(plan.capitalized).font(.caption2).foregroundStyle(.secondary) }
                if reading.lastRefreshError != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Stale: refresh failed, last successful reading shown") }
                else if reading.availability == .available { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Text("—").foregroundStyle(.secondary) }
            }
            if let error = reading.lastRefreshError {
                Label(AILimitsStalePresentation.message(updatedAt: reading.updatedAt, error: error), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let identity = reading.verifiedAccountIdentity {
                Text("Verified account: " + identity).font(.caption2).foregroundStyle(.secondary)
            }
            if reading.windows.isEmpty, let message = reading.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !reading.windows.isEmpty {
                ForEach(reading.windows) { window in
                    limitWindow(window, provider: reading.provider)
                }
            }
            if reading.availability != .available, reading.provider != .claude, reading.provider != .codex {
                Text(reading.provider.setupInstructions)
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                if let command = reading.provider.statusLineSetupCommand {
                    HStack {
                        Button("Copy statusLine value") {
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
                    .font(.caption2)
                    Text("If Claude Code already has a statusLine, merge this file-writing step into its command to preserve the current terminal display.")
                        .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let updatedAt = reading.updatedAt {
                Text("Reading as of \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func limitWindow(_ window: AILimitWindow, provider: AIProvider) -> some View {
        let percent: Int? = configuration.aiLimitsRepresentation == .remaining ? window.remainingPercent : window.usedPercent
        let visualPercent = percent.map { min(100, max(0, $0)) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name).font(.caption.weight(.medium))
                Spacer()
                Text(percent.map { "\($0)%" } ?? "—")
                    .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                if let reset = window.resetsAt {
                    Text("Resets \(reset.formatted(.relative(presentation: .numeric)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let percent {
                switch configuration.aiLimitsLayout {
                case .numbers:
                    HStack { Text(configuration.aiLimitsRepresentation.title); Spacer(); Text("\(percent)%").monospacedDigit() }
                        .font(.caption2).foregroundStyle(.secondary)
                case .bars:
                    ProgressView(value: Double(visualPercent ?? 0), total: 100)
                        .tint((visualPercent ?? 0) > 90 ? .orange : .cyan)
                case .rings:
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(.quaternary, lineWidth: 4)
                            Circle().trim(from: 0, to: Double(visualPercent ?? 0) / 100).stroke((visualPercent ?? 0) > 90 ? .orange : .cyan,
                                                                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(percent)").font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                        }.frame(width: 28, height: 28)
                        Text("\(configuration.aiLimitsRepresentation.title) · \(provider.title)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
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
    private func refresh() async {
        let requestID = UUID()
        refreshRequestID = requestID
        isRefreshing = true
        defer { if refreshRequestID == requestID { isRefreshing = false } }
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if width > 0 {
                WidgetHeader(kind: "AI Activity", title: configuration.aiActivityProvider.shortName,
                             trailing: layout == .compact || width <= 54 ? nil : configuration.aiActivityRange.activityTitle,
                             symbol: configuration.aiActivityProvider == .codex ? "terminal" : "sparkle")
            }
            if layout == .trend && width > 54 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    MetricText(value: value, unit: snapshot?.available == true ? "tokens" : "", size: 19)
                    Spacer(minLength: 2)
                    if let secondary { Text(secondary).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let snapshot, snapshot.available, snapshot.points.count > 1 {
                    MicroSparkline(values: snapshot.points.map { Double($0.totalTokens) }, color: WidgetPalette.accent("AI Activity")).frame(height: 8)
                }
            } else {
                MetricText(value: value, unit: width > 54 && snapshot?.available == true ? "tokens" : "", size: layout == .compact ? 18 : 19)
                if layout == .standard && width > 54, let secondary { Text(secondary).font(.system(size: 8)).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, width > 54 ? 9 : 4).frame(maxWidth: .infinity, alignment: .leading).frame(height: 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(configuration.aiActivityProvider.title) AI Activity")
            .accessibilityValue(snapshot?.available == true ? snapshot!.tokensText + (secondary.map { ", " + $0 } ?? "") : "No local activity. Open for setup.")
            .help(snapshot.map { "\($0.provider.title) · \($0.tokensText) · \($0.range.activityTitle). Based on available local logs. " + ($0.range == .today ? "Sparkline shows the last 7 days." : "") } ?? "Open to set up local activity")
    }
    private var value: String {
        guard let snapshot, snapshot.available else { return snapshot == nil ? "Set up" : "No data" }
        return AIActivityFormatting.tokens(snapshot.totals.totalTokens) + (snapshot.partial && !snapshot.estimated ? "+" : "")
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
            HStack {
                Text("Local usage").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if refreshing { ProgressView().controlSize(.mini).frame(width: 24, height: 24).help("Updating local activity") }
                else {
                    Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                        .buttonStyle(.borderless).help("Refresh local activity").accessibilityLabel("Refresh AI Activity")
                }
                Menu {
                    Picker("Provider", selection: $provider) {
                        ForEach([AIProvider.codex, .claude, .grok]) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Picker("Chart", selection: $chartStyle) { ForEach(AIActivityChartStyle.allCases) { Text($0.title).tag($0) } }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 20, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Provider and chart options").accessibilityLabel("Activity options")
            }
            HStack(spacing: 7) {
                AIProviderGlyph(provider: provider).frame(width: 16, height: 16)
                Menu {
                    ForEach([AIProvider.codex, .claude, .grok]) { value in Button(value.title) { provider = value } }
                } label: { Text(provider.title).font(.system(size: 13, weight: .medium)) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Activity provider").accessibilityValue(provider.title)
                Spacer()
                Picker("Activity range", selection: $range) {
                    ForEach(AIActivityRange.allCases) { Text($0.activityTitle).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 208).controlSize(.small)
            }
            if let s = snapshot, s.available {
                metrics(s)
                if chartStyle != .totals { chart(s) }
                if s.totals.requests > 0 || s.totals.reportedCostUSD != nil {
                    HStack {
                        if s.totals.requests > 0 { Text("\(s.totals.requests.formatted()) requests") }
                        Spacer()
                        if let cost = s.totals.reportedCostUSD { Text("Reported cost \(cost.formatted(.currency(code: "USD")))") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Based on local \(provider.title) session logs.").font(.caption).foregroundStyle(.secondary)
                    if s.partial || s.estimated {
                        Label(s.estimated ? "Local estimate, not a billing total." : "Some records couldn’t be read. Totals may be incomplete.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.help(s.sourceDescription)
            } else { emptyState }
            if let recoveryMessage { Text(recoveryMessage).font(.caption).foregroundStyle(.secondary) }
            if let s = snapshot, s.available {
                DataSourceProvenanceView(provenance: .aiActivity(snapshot: s, error: coordinator.errors[query]))
            }
            Divider()
            HStack(spacing: 6) {
                if failed {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    Text(snapshot?.available == true ? "Refresh failed · saved activity shown" : "Local activity couldn’t be read")
                } else if refreshing { Text(snapshot == nil ? "Reading local history…" : "Updating…") }
                else if let s = snapshot { Text("Read \(s.fetchedAt.formatted(date: .abbreviated, time: .shortened))") }
                else { Text("Local activity only") }
                Spacer(minLength: 0)
                if failed { Button("Retry", action: refresh).buttonStyle(.borderless).disabled(refreshing) }
            }.font(.caption).foregroundStyle(.secondary).accessibilityElement(children: .combine)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metrics(_ s: AIActivitySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            metric("Tokens", value: AIActivityFormatting.tokens(s.totals.totalTokens) + (s.partial && !s.estimated ? "+" : ""), primary: true)
                .help(s.tokensText + ". " + s.sourceDescription)
            Spacer(minLength: 0)
            metric("Sessions", value: AIActivityFormatting.tokens(Int64(s.totals.sessions)))
                .help("Distinct local sessions with activity in \(s.range.activityDescription). Daily counts count each session once per day.")
            metric("Tool calls", value: AIActivityFormatting.tokens(Int64(s.totals.toolCalls)))
        }.padding(14).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 14))
    }
    private func metric(_ title: String, value: String, primary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: primary ? 30 : 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func chart(_ s: AIActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Token activity").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(range == .today ? "Last 7 days" : range.activityDescription).font(.caption).foregroundStyle(.secondary)
            }
            Chart(s.points) { point in
                if chartStyle == .bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Tokens", point.totalTokens))
                        .foregroundStyle(Color.accentColor.opacity(0.8)).cornerRadius(3)
                } else {
                    AreaMark(x: .value("Day", point.date), y: .value("Tokens", point.totalTokens)).foregroundStyle(Color.accentColor.opacity(0.10)).interpolationMethod(.linear)
                    LineMark(x: .value("Day", point.date), y: .value("Tokens", point.totalTokens)).foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round)).interpolationMethod(.linear)
                }
            }
            .chartYScale(domain: 0...max(1, Double(s.points.map(\.totalTokens).max() ?? 0) * 1.12))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
                    AxisValueLabel { if let tokens = value.as(Double.self) { Text(AIActivityFormatting.tokens(Int64(tokens))).font(.system(size: 10)) } }
                }
            }
            .frame(height: 136).accessibilityLabel("\(provider.title) token activity by day, \(range == .today ? "last 7 days" : range.activityDescription)")
        }
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: failed ? "exclamationmark.circle" : "chart.bar.xaxis").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
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

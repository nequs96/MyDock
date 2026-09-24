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

private struct AILimitsCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var selectedProvider: AIProvider? {
        if configuration.aiLimitsVisibleProviders.contains(configuration.aiLimitsCompactProvider) {
            return configuration.aiLimitsCompactProvider
        }
        return configuration.aiLimitsProviderOrder.first(where: configuration.aiLimitsVisibleProviders.contains)
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.cyan)
            if let provider = selectedProvider {
                Text(provider.shortName).font(.system(size: 7, weight: .semibold)).lineLimit(1)
                let reading = configuration.aiLimitsSnapshot?.reading(for: provider)
                if let reading, !reading.windows.isEmpty {
                    ForEach(Array(reading.windows.prefix(2))) { window in
                        HStack(spacing: 2) {
                            Text(window.durationMinutes.map(compactWindowTitle) ?? "Limit")
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(compactPercent(window, mode: configuration.aiLimitsRepresentation))
                                .monospacedDigit().frame(alignment: .trailing)
                        }
                        .font(.system(size: 7, weight: .semibold))
                    }
                } else {
                    Text("—").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                }
            } else {
                Text("No limits").font(.system(size: 7, weight: .medium)).lineLimit(1)
            }
        }
        .frame(width: 54, height: 54)
        .help(selectedProvider.flatMap { configuration.aiLimitsSnapshot?.reading(for: $0) }
            .map { "\($0.provider.title) limits · " + $0.windows.map { limitLabel($0, mode: configuration.aiLimitsRepresentation) }.joined(separator: ", ") }
            ?? "AI Limits · Refresh in the popout")
    }
}

private struct AILimitsPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var orderedProviders: [AIProvider] {
        var result = configuration.aiLimitsProviderOrder.filter(AIProvider.allCases.contains)
        for provider in AIProvider.allCases where !result.contains(provider) { result.append(provider) }
        return result
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

            controls
            Divider()
            if visibleReadings.isEmpty {
                Text("Turn on a provider to show its usage window here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(visibleReadings) { reading in providerSection(reading) }
            }
            if let fetchedAt = configuration.aiLimitsSnapshot?.fetchedAt {
                Label("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text("A dash means unavailable. MyDock reads Codex's local app-server rate-limit API without starting a task. It does not infer percentages or refresh limits by spending model tokens.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 385, alignment: .leading)
        .frame(minHeight: 220, alignment: .topLeading)
        .task(id: configuration.aiLimitsVisibleProviders.map(\.rawValue).joined(separator: ",")) {
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: 60) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Layout").foregroundStyle(.secondary)
                Picker("Layout", selection: layoutBinding) {
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
                if reading.availability == .available { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Text("—").foregroundStyle(.secondary) }
            }
            if reading.windows.isEmpty {
                Text(reading.message ?? reading.provider.setupInstructions)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(reading.windows) { window in
                    limitWindow(window, provider: reading.provider)
                }
            }
            if reading.availability != .available {
                Text(reading.provider.setupInstructions)
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if let updatedAt = reading.updatedAt {
                Text("Provider update \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func limitWindow(_ window: AILimitWindow, provider: AIProvider) -> some View {
        let percent: Int? = configuration.aiLimitsRepresentation == .remaining ? window.remainingPercent : window.usedPercent
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
                    ProgressView(value: Double(percent), total: 100)
                        .tint(percent > 90 ? .orange : .cyan)
                case .rings:
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(.quaternary, lineWidth: 4)
                            Circle().trim(from: 0, to: Double(percent) / 100).stroke(percent > 90 ? .orange : .cyan,
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let now = Date.now
            let reading = try await Task.detached(priority: .utility) { try CodexAppServerLimitReader.read(now: now) }.value
            let readings = orderedProviders.map { provider in
                if provider == .codex { return reading }
                let message = provider == .claude || provider == .grok || provider == .antigravity
                    ? "Waiting for a supported provider-reported limit update."
                    : "No authenticated quota reader is available in this build."
                return AIProviderLimitReading(provider: provider, availability: .unavailable, plan: nil,
                                              windows: [], updatedAt: nil, message: message)
            }
            let next = AILimitsSnapshot(fetchedAt: now, readings: readings)
            update { $0.aiLimitsSnapshot = next }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AIActivityCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: AIActivitySnapshot? { configuration.aiActivitySnapshot }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 15, weight: .medium)).foregroundStyle(.cyan)
            if let snapshot, snapshot.available {
                Text(compactTokens(snapshot.totals.totalTokens)).font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(configuration.aiActivityProvider.shortName).font(.system(size: 7, weight: .medium)).lineLimit(1)
            } else {
                Text("Activity").font(.system(size: 8, weight: .medium)).lineLimit(1)
            }
            if snapshot?.partial == true || snapshot?.estimated == true {
                Circle().fill(.orange).frame(width: 4, height: 4)
            }
        }
        .frame(width: 54, height: 54)
        .help(snapshot.map { "\($0.provider.title) Activity · \($0.tokensText) · \($0.range.title)" } ?? "AI Activity · Open to refresh local history")
    }
}

private struct AIActivityPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var isRefreshing = false

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: AIActivitySnapshot? { configuration.aiActivitySnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.cyan)
                Text("AI Activity").font(.headline)
                Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(isRefreshing)
                if isRefreshing { ProgressView().controlSize(.small) }
            }
            HStack {
                Picker("Provider", selection: providerBinding) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
                Picker("Date range", selection: rangeBinding) {
                    ForEach(AIActivityRange.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
                Picker("Chart style", selection: chartStyleBinding) {
                    ForEach(AIActivityChartStyle.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            if let snapshot {
                metricSummary(snapshot)
                if configuration.aiActivityChartStyle != .totals, snapshot.available { activityChart(snapshot) }
                Text(snapshot.sourceDescription).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let message = snapshot.message {
                    Label(message, systemImage: snapshot.available ? "exclamationmark.triangle" : "info.circle")
                        .font(.caption).foregroundStyle(snapshot.available ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("Refresh to read local usage counters. MyDock does not retain prompts, tool contents, file paths, or session transcripts.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 385, alignment: .leading)
        .frame(minHeight: 220, alignment: .topLeading)
        .task(id: "\(configuration.aiActivityProvider.rawValue)|\(configuration.aiActivityRange.rawValue)") {
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: 60) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    @ViewBuilder
    private func metricSummary(_ snapshot: AIActivitySnapshot) -> some View {
        HStack(alignment: .top, spacing: 15) {
            activityMetric("Tokens", value: snapshot.tokensText)
            activityMetric("Sessions", value: snapshot.totals.sessions.formatted())
            activityMetric("Tool calls", value: snapshot.totals.toolCalls.formatted())
            if snapshot.totals.requests > 0 { activityMetric("Requests", value: snapshot.totals.requests.formatted()) }
            if let cost = snapshot.totals.reportedCostUSD { activityMetric("Reported cost", value: cost.formatted(.currency(code: "USD"))) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func activityChart(_ snapshot: AIActivitySnapshot) -> some View {
        switch configuration.aiActivityChartStyle {
        case .sparkline:
            Chart(snapshot.points) { point in
                LineMark(x: .value("Day", point.date), y: .value("Tokens", point.totalTokens))
                    .foregroundStyle(.cyan).interpolationMethod(.catmullRom)
                AreaMark(x: .value("Day", point.date), y: .value("Tokens", point.totalTokens))
                    .foregroundStyle(.cyan.opacity(0.12)).interpolationMethod(.catmullRom)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 110)
            .accessibilityLabel("\(snapshot.provider.title) token activity by local day")
        case .bars:
            Chart(snapshot.points) { point in
                BarMark(x: .value("Day", point.date), y: .value("Tokens", point.totalTokens))
                    .foregroundStyle(.cyan.gradient)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: 110)
            .accessibilityLabel("\(snapshot.provider.title) token activity by local day")
        case .totals:
            EmptyView()
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(get: { configuration.aiActivityProvider }, set: { value in update { $0.aiActivityProvider = value; $0.aiActivitySnapshot = nil } })
    }
    private var rangeBinding: Binding<AIActivityRange> {
        Binding(get: { configuration.aiActivityRange }, set: { value in update { $0.aiActivityRange = value; $0.aiActivitySnapshot = nil } })
    }
    private var chartStyleBinding: Binding<AIActivityChartStyle> {
        Binding(get: { configuration.aiActivityChartStyle }, set: { value in update { $0.aiActivityChartStyle = value } })
    }
    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let provider = configuration.aiActivityProvider
        let range = configuration.aiActivityRange
        let now = Date.now
        let timeZone = TimeZone.current
        let result = await Task.detached(priority: .utility) { AIActivityReader.read(provider: provider, range: range, now: now, timeZone: timeZone) }.value
        update { value in
            guard value.aiActivityProvider == provider, value.aiActivityRange == range else { return }
            value.aiActivitySnapshot = result
        }
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

private func compactWindowTitle(_ minutes: Int) -> String {
    switch minutes {
    case 300: "5h"
    case 10_080: "7d"
    case let value where value >= 1_440: "\(value / 1_440)d"
    default: "\(minutes)m"
    }
}

private func compactTokens(_ value: Int64) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 10_000 { return "\(value / 1_000)k" }
    return value.formatted()
}

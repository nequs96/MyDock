import SwiftUI

struct WeatherWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WeatherCompactWidgetView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WeatherPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

private struct WeatherCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @Environment(\.widgetLayout) private var widgetLayout
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var errorMessage: String?
    @State private var refreshRequestID = UUID()
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }

    private var currentConfiguration: WidgetConfiguration? {
        store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id && $0.widgetKind == "Weather" })?.widgetConfiguration
    }

    var body: some View {
        WeatherDockFace(configuration: configuration)
        .frame(width: contentWidth, height: 54)
        .help(tooltip)
        .task(id: requestKey) {
            await refreshIfConfigured()
            for await _ in RefreshScheduler.shared.ticks(every: 10 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfConfigured()
            }
        }
        .onDisappear { refreshRequestID = UUID() }
    }

    private var requestKey: String {
        "\(configuration.weatherLocation?.id ?? "unset")|\(configuration.weatherUnit.rawValue)"
    }

    private var tooltip: String {
        guard let forecast = configuration.cachedWeatherForecast else {
            return errorMessage ?? "Configure a city in Weather"
        }
        return "\(configuration.weatherLocation?.displayName ?? "Weather") · \(WeatherCode.description(forecast.weatherCode)) · Updated \(forecast.fetchedAt.formatted(date: .omitted, time: .shortened))"
    }

    private func refreshIfConfigured() async {
        guard let location = configuration.weatherLocation else { return }
        let requestedUnit = configuration.weatherUnit
        let requestID = UUID()
        refreshRequestID = requestID
        do {
            let forecast = try await WeatherService.shared.forecast(for: location, unit: requestedUnit)
            guard refreshRequestID == requestID, !Task.isCancelled,
                  let current = currentConfiguration,
                  current.weatherLocation?.id == location.id,
                  current.weatherUnit == requestedUnit else { return }
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                guard value.weatherLocation?.id == location.id, value.weatherUnit == requestedUnit else { return }
                value.cachedWeatherForecast = forecast
            }
            errorMessage = nil
        } catch {
            guard refreshRequestID == requestID, !Task.isCancelled,
                  let current = currentConfiguration,
                  current.weatherLocation?.id == location.id,
                  current.weatherUnit == requestedUnit else { return }
            DiagnosticsService.shared.record(.weatherRefreshFailed)
            errorMessage = error.localizedDescription
        }
    }
}

private struct WeatherPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var setupDrafts = WidgetSetupDraftStore.shared
    @State private var isSearching = false
    @State private var isLocating = false
    @State private var isLoading = false
    @State private var refreshRequestID = UUID()
    @State private var searchRequestID = UUID()
    @State private var locationRequestID = UUID()
    @State private var locationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var unitSelection = WeatherTemperatureUnit.celsius.rawValue
    @State private var layoutSelection = WeatherWidgetLayout.current.rawValue
    @State private var forecastHours = 3
    @State private var backgroundSelection = WeatherBackground.themed.rawValue
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }
    private var location: WeatherLocation? { configuration.weatherLocation }
    private var forecast: WeatherForecast? { configuration.cachedWeatherForecast }
    private var requestKey: String { "\(location?.id ?? "unset")|\(configuration.weatherUnit.rawValue)" }
    private var setupDraft: WeatherLocationDraft { setupDrafts.weatherDraft(for: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            if let forecast { forecastContent(forecast) }
            if isLoading && forecast == nil {
                GroupedSection {
                    WidgetPopoutRow {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading forecast…").font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let errorMessage {
                WidgetPopoutCaption(forecast == nil ? errorMessage : "Showing saved forecast. \(errorMessage)", color: .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                WidgetPopoutSectionHeader("Location") {
                    if location != nil {
                        HStack(spacing: 6) {
                            if isLoading { ProgressView().controlSize(.mini).accessibilityLabel("Loading forecast") }
                            Button("Refresh") { refresh(force: true) }.disabled(isLoading)
                        }
                    }
                }
                GroupedSection(footer: forecast.map { "Updated \($0.fetchedAt.formatted(date: .omitted, time: .shortened)) · forecast times: \($0.timeZoneIdentifier)" },
                               separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    if let location, !setupDraft.isChangingLocation {
                        GroupedRow(location.displayName) {
                            Button("Change") {
                                setupDrafts.updateWeatherDraft(for: item.id) {
                                    $0.isChangingLocation = true
                                    $0.searchText = ""
                                    $0.searchResults = []
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if location == nil || setupDraft.isChangingLocation {
                        locationSearchSection
                    }
                }
            }

            settingsSection

            WidgetPopoutCaption("Weather and places: Open-Meteo · Geocoding data: GeoNames", color: Color.secondary.opacity(0.8))
        }
        .onAppear {
            unitSelection = configuration.weatherUnit.rawValue
            layoutSelection = configuration.weatherLayout.rawValue
            forecastHours = configuration.weatherForecastHours
            backgroundSelection = configuration.weatherBackground.rawValue
        }
        .onChange(of: unitSelection) { rawValue in
            guard let value = WeatherTemperatureUnit(rawValue: rawValue) else { return }
            updateConfiguration { $0.selectWeatherUnit(value) }
        }
        .onChange(of: layoutSelection) { rawValue in
            guard let value = WeatherWidgetLayout(rawValue: rawValue) else { return }
            updateConfiguration { $0.weatherLayout = value }
        }
        .onChange(of: forecastHours) { value in updateConfiguration { $0.weatherForecastHours = min(max(value, 1), 6) } }
        .onChange(of: backgroundSelection) { rawValue in
            guard let value = WeatherBackground(rawValue: rawValue) else { return }
            updateConfiguration { $0.weatherBackground = value }
        }
        .onChange(of: configuration.weatherUnit) { unitSelection = $0.rawValue }
        .onChange(of: configuration.weatherLayout) { layoutSelection = $0.rawValue }
        .onChange(of: configuration.weatherForecastHours) { forecastHours = $0 }
        .onChange(of: configuration.weatherBackground) { backgroundSelection = $0.rawValue }
        .task(id: requestKey) {
            await refreshIfConfigured()
            for await _ in RefreshScheduler.shared.ticks(every: 10 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfConfigured()
            }
        }
        .onDisappear {
            refreshRequestID = UUID()
            searchRequestID = UUID()
            locationRequestID = UUID()
            locationTask?.cancel()
            locationTask = nil
            isLoading = false
            isSearching = false
            isLocating = false
        }
    }

    /// Rows of the Location section while choosing a city: search, results, current location.
    @ViewBuilder private var locationSearchSection: some View {
        WidgetPopoutRow {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search for a city", text: searchTextBinding)
                    .textFieldStyle(.plain)
                    .onSubmit(search)
                if isSearching { ProgressView().controlSize(.small).accessibilityLabel("Searching cities") }
                Button("Search", action: search).buttonStyle(.borderless).disabled(isSearching)
                Button("Clear") { clearSearchDraft(keepChanging: location != nil && setupDraft.isChangingLocation) }
                    .buttonStyle(.borderless)
                    .disabled(setupDraft.searchText.isEmpty && setupDraft.searchResults.isEmpty)
            }
        }
        ForEach(setupDraft.searchResults) { result in
            Button { select(result) } label: {
                WidgetPopoutRow {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.name).font(DockDesign.Grouped.titleFont)
                            Text([result.administrativeArea, result.country].compactMap { $0 }.joined(separator: ", "))
                                .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(DockDesign.accent).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose \(result.displayName)")
        }
        GroupedRow(isLocating ? "Finding current location…" : "Use Current Location", role: .button, symbol: "location.fill", action: useCurrentLocation)
            .disabled(isLocating)
            .help("Location permission is only requested if you choose this.")
        if location != nil && setupDraft.isChangingLocation {
            GroupedRow("Cancel", role: .button, action: cancelLocationChange)
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(get: { setupDraft.searchText }, set: { value in
            let newText = String(value.prefix(120))
            guard newText != setupDraft.searchText else { return }
            searchRequestID = UUID()
            isSearching = false
            setupDrafts.updateWeatherDraft(for: item.id) {
                $0.searchText = newText
                $0.searchResults = []
            }
        })
    }

    private var settingsSection: some View {
        GroupedSection("Options", footer: configuration.weatherLayout == .conditions ? "Units change °C / °F. Wind stays in km/h and precipitation in mm." : nil,
                       separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            GroupedRow("Show") {
                Picker("Popover content", selection: $layoutSelection) {
                    ForEach(WeatherWidgetLayout.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .labelsHidden().fixedSize().accessibilityLabel("Popover content")
            }
            GroupedRow("Units") {
                Picker("Units", selection: $unitSelection) {
                    ForEach(WeatherTemperatureUnit.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().accessibilityLabel("Units")
            }
            GroupedRow("Background") {
                Picker("Background", selection: $backgroundSelection) {
                    ForEach(WeatherBackground.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .labelsHidden().fixedSize().accessibilityLabel("Background")
            }
            WidgetStepperRow(title: "Forecast", value: "\(forecastHours) hours", amount: $forecastHours, range: 1...6, step: 1)
                .disabled(configuration.weatherLayout != .hourlyForecast)
        }
    }

    @ViewBuilder private func forecastContent(_ forecast: WeatherForecast) -> some View {
        currentSummary(forecast)
        switch configuration.weatherLayout {
        case .current: EmptyView()
        case .conditions: conditionDetails(forecast)
        case .hourlyForecast: hourlyList(forecast)
        }
    }

    /// The temperature as the one large value, the condition glyph above it and one caption line.
    private func currentSummary(_ forecast: WeatherForecast) -> some View {
        VStack(spacing: 2) {
            Image(systemName: WeatherCode.symbol(forecast.weatherCode, isDay: forecast.isDay))
                .font(.system(size: 30)).symbolRenderingMode(.hierarchical).foregroundStyle(.primary)
                .accessibilityHidden(true)
            WidgetPopoutHero(value: WeatherDockTemperatureFormatter.text(forecast.temperature, unit: configuration.weatherUnit),
                             caption: WeatherCode.description(forecast.weatherCode)
                                + " · Feels like " + WeatherDockTemperatureFormatter.text(forecast.apparentTemperature, unit: configuration.weatherUnit))
            if let location { Text(location.name).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(weatherBackground(for: forecast.weatherCode), in: RoundedRectangle(cornerRadius: DockDesign.Grouped.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func conditionDetails(_ forecast: WeatherForecast) -> some View {
        GroupedSection("Conditions", separatorInset: DockDesign.Grouped.separatorInset) {
            GroupedRow("Humidity", symbol: "humidity", color: .gray, value: "\(forecast.relativeHumidity)%")
            GroupedRow("Wind", symbol: "wind", color: .gray, value: "\(Int(forecast.windSpeed.rounded())) km/h")
            GroupedRow("Precipitation", symbol: "drop.fill", color: .gray,
                       value: "\(forecast.precipitation.formatted(.number.precision(.fractionLength(0...1)))) mm")
        }
    }

    /// Upcoming hours in one grouped surface: no boxes per hour.
    private func hourlyList(_ forecast: WeatherForecast) -> some View {
        let hours = forecast.hourly.filter { $0.timestamp > .now }.prefix(configuration.weatherForecastHours)
        return GroupedSection("Next Hours") {
            DockScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(hours)) { hour in
                        VStack(spacing: 5) {
                            Text(hour.timestamp.formattedTime(in: forecast.timeZoneIdentifier))
                                .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                            Image(systemName: WeatherCode.symbol(hour.weatherCode, isDay: true))
                                .font(.system(size: 17)).symbolRenderingMode(.hierarchical).frame(height: 20)
                                .accessibilityHidden(true)
                            Text(WeatherDockTemperatureFormatter.text(hour.temperature, unit: configuration.weatherUnit))
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            if let chance = hour.precipitationProbability {
                                Label("\(chance)%", systemImage: "drop.fill").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minWidth: 64)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func weatherBackground(for code: Int) -> some ShapeStyle {
        if accessibility.reduceTransparency { return AnyShapeStyle(DockDesign.Grouped.fill) }
        if configuration.weatherBackground == .translucent { return AnyShapeStyle(DockDesign.Grouped.fill) }
        let color: Color = code >= 95 ? .purple : code >= 51 ? .blue : code >= 3 ? .gray : .orange
        return AnyShapeStyle(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.06)], startPoint: .top, endPoint: .bottom))
    }

    private func search() {
        let query = setupDraft.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { errorMessage = WeatherServiceError.invalidSearch.localizedDescription; return }
        let requestID = UUID()
        searchRequestID = requestID
        isSearching = true
        errorMessage = nil
        Task {
            defer { if searchRequestID == requestID { isSearching = false } }
            do {
                let results = try await WeatherService.shared.searchLocations(query)
                guard searchRequestID == requestID, !Task.isCancelled, widgetStillExists,
                      setupDraft.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                setupDrafts.updateWeatherDraft(for: item.id) { $0.searchResults = results }
            } catch {
                guard searchRequestID == requestID, !Task.isCancelled, widgetStillExists,
                      setupDraft.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                setupDrafts.updateWeatherDraft(for: item.id) { $0.searchResults = [] }
                DiagnosticsService.shared.record(.weatherSearchFailed)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func select(_ location: WeatherLocation) {
        guard widgetStillExists else { return }
        searchRequestID = UUID()
        locationRequestID = UUID()
        locationTask?.cancel()
        locationTask = nil
        refreshRequestID = UUID()
        isSearching = false
        isLocating = false
        isLoading = false
        setupDrafts.clearDrafts(for: item.id)
        errorMessage = nil
        updateConfiguration { value in
            value.weatherLocation = location
            value.cachedWeatherForecast = nil
        }
    }

    private func clearSearchDraft(keepChanging: Bool) {
        searchRequestID = UUID()
        isSearching = false
        setupDrafts.updateWeatherDraft(for: item.id) {
            $0.searchText = ""
            $0.searchResults = []
            $0.isChangingLocation = keepChanging
        }
    }

    private func cancelLocationChange() {
        guard location != nil else { return }
        searchRequestID = UUID()
        locationRequestID = UUID()
        locationTask?.cancel()
        locationTask = nil
        isSearching = false
        isLocating = false
        setupDrafts.clearDrafts(for: item.id)
    }

    private func useCurrentLocation() {
        let previousTask = locationTask
        previousTask?.cancel()
        let requestID = UUID()
        locationRequestID = requestID
        isLocating = true
        errorMessage = nil
        locationTask = Task { @MainActor in
            if let previousTask { await previousTask.value }
            defer {
                if locationRequestID == requestID {
                    isLocating = false
                    locationTask = nil
                }
            }
            guard !Task.isCancelled else { return }
            do {
                let currentLocation = try await CurrentLocationService.shared.currentLocation()
                guard locationRequestID == requestID, !Task.isCancelled, widgetStillExists else { return }
                select(currentLocation)
            } catch {
                guard locationRequestID == requestID, !Task.isCancelled, widgetStillExists else { return }
                DiagnosticsService.shared.record(.weatherLocationFailed)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refresh(force: Bool) {
        Task { await loadForecast(force: force) }
    }

    private func refreshIfConfigured() async {
        await loadForecast(force: false)
    }

    private func loadForecast(force: Bool) async {
        guard let location else { return }
        let requestedUnit = configuration.weatherUnit
        let requestID = UUID()
        refreshRequestID = requestID
        isLoading = true
        defer { if refreshRequestID == requestID { isLoading = false } }
        do {
            let result = try await WeatherService.shared.forecast(for: location, unit: requestedUnit, forceRefresh: force)
            guard refreshRequestID == requestID, !Task.isCancelled,
                  let current = currentConfiguration,
                  current.weatherLocation?.id == location.id,
                  current.weatherUnit == requestedUnit else { return }
            updateConfiguration { $0.cachedWeatherForecast = result }
            errorMessage = nil
        } catch {
            guard refreshRequestID == requestID, !Task.isCancelled,
                  let current = currentConfiguration,
                  current.weatherLocation?.id == location.id,
                  current.weatherUnit == requestedUnit else { return }
            DiagnosticsService.shared.record(.weatherRefreshFailed)
            errorMessage = error.localizedDescription
        }
    }

    private var widgetStillExists: Bool { currentConfiguration != nil }

    private var currentConfiguration: WidgetConfiguration? {
        store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id && $0.widgetKind == "Weather" })?.widgetConfiguration
    }

    private func updateConfiguration(_ update: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: update)
    }
}

enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear sky"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Rain showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "Conditions unavailable"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 71...77, 85...86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.sun.fill"
        }
    }
}

extension Date {
    func formattedTime(in timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)
        return formatter.string(from: self)
    }
}

import SwiftUI

struct WeatherWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WeatherCompactWidgetView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WeatherPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

/// When a forecast reads as stale: the popout's 30-minute rule, applied to the Dock face too.
enum WeatherFreshness {
    static let maximumAge: TimeInterval = 30 * 60

    static func isStale(fetchedAt: Date?, failed: Bool, now: Date = .now) -> Bool {
        guard let fetchedAt else { return false }
        return failed || now.timeIntervalSince(fetchedAt) > maximumAge
    }

    /// "Updated 5 minutes ago", "Updated yesterday": never a bare time without its day.
    static func updatedText(_ fetchedAt: Date) -> String {
        "Updated " + fetchedAt.formatted(.relative(presentation: .named))
    }
}

/// The Dock face's stale mark: the same small warning dot as the coordinator families.
private struct WeatherStaleDot: View {
    @Environment(\.dockModuleRadius) private var moduleRadius
    @DockAccessibilityStyle() private var accessibility
    private var inset: CGFloat { max(6, min(10, moduleRadius * 0.45)) }
    var body: some View {
        Circle().fill(WidgetPalette.warning)
            .overlay { if accessibility.contrast == .increased { Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1) } }
            .frame(width: 6, height: 6)
            .padding(.top, inset).padding(.trailing, inset)
            .accessibilityLabel("Forecast is out of date")
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
        .overlay(alignment: .topTrailing) {
            if WeatherFreshness.isStale(fetchedAt: configuration.cachedWeatherForecast?.fetchedAt, failed: errorMessage != nil) {
                WeatherStaleDot()
            }
        }
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
        return "\(configuration.weatherLocation?.displayName ?? "Weather") · \(WeatherCode.description(forecast.weatherCode)) · "
            + WeatherFreshness.updatedText(forecast.fetchedAt)
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
            // A forecast is a provider reading, not an authored edit: it publishes even while saving is disabled.
            let result = store.publishRuntimeReadings(itemID: item.id, in: profileID) { value in
                guard value.weatherLocation?.id == location.id, value.weatherUnit == requestedUnit else { return }
                value.cachedWeatherForecast = forecast
            }
            if result == .accepted || result == .unchanged { errorMessage = nil }
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
    /// Location and options sit behind a final, collapsed disclosure once a city is set.
    @State private var settingsExpanded = false
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
                WidgetPopoutCaption(forecast == nil ? errorMessage : "Showing saved forecast. \(errorMessage)", color: WidgetPalette.warning)
            }

            // Without a city, choosing one is the primary action; afterwards it is setup like the options.
            if location == nil {
                locationSection
                WidgetPopoutSettingsDisclosure(isExpanded: $settingsExpanded) { settingsSection }
            } else {
                WidgetPopoutSettingsDisclosure(summary: location?.name, isExpanded: $settingsExpanded) {
                    locationSection
                    settingsSection
                }
            }
            // Attribution stays visible whether or not the settings are open.
            WidgetPopoutCaption(WeatherCopy.attribution)
        }
        // The forecast's age and the one refresh control live in the shell's header.
        .widgetPopoutRefresh(location == nil ? nil
            : WidgetPopoutRefresh(updatedAt: forecast?.fetchedAt, isRefreshing: isLoading, failed: errorMessage != nil,
                                  maximumAge: WeatherFreshness.maximumAge, action: { refresh(force: true) }))
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

    /// The city: its name with Change, or the search while choosing one.
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetPopoutSectionHeader("Location")
            GroupedSection(footer: forecast.flatMap { WeatherCopy.timeZoneFooter(forecastTimeZone: $0.timeZoneIdentifier) },
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
        GroupedSection("Options", footer: configuration.weatherLayout == .conditions ? "Wind is in km/h and precipitation in mm." : nil,
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
            // Only the hourly forecast has a length; other layouts show no disabled control for it.
            if WeatherCopy.showsForecastLength(configuration.weatherLayout) {
                WidgetStepperRow(title: "Forecast", value: forecastHours == 1 ? "1 hour" : "\(forecastHours) hours", amount: $forecastHours, range: 1...6, step: 1)
            }
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

    /// The temperature as the one large value, the condition glyph above it and one caption line, on the
    /// condition card. Glyph, place and card are the hero's decoration: the settings sheet hides them together.
    private func currentSummary(_ forecast: WeatherForecast) -> some View {
        WidgetPopoutHeroGroup { currentSummaryCard(forecast) }
    }

    private func currentSummaryCard(_ forecast: WeatherForecast) -> some View {
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

    /// Upcoming hours in one grouped surface: no boxes per hour. The columns share the width when they
    /// fit, and scroll only when they do not. Each hour's glyph is day or night for that hour.
    @ViewBuilder private func hourlyList(_ forecast: WeatherForecast) -> some View {
        let hours = Array(forecast.hourly.filter { $0.timestamp > .now }.prefix(configuration.weatherForecastHours))
        if hours.isEmpty {
            // A forecast older than its saved hours has none left to show until the next refresh.
            WidgetPopoutCaption("Hourly forecast returns with the next refresh.")
        } else {
            hourlyColumns(hours, forecast: forecast)
        }
    }

    private func hourlyColumns(_ hours: [WeatherHour], forecast: WeatherForecast) -> some View {
        GroupedSection("Next Hours") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(hours) { hour in hourColumn(hour, forecast: forecast).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, 6)
                DockScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(hours) { hour in hourColumn(hour, forecast: forecast) }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func hourColumn(_ hour: WeatherHour, forecast: WeatherForecast) -> some View {
        let isDay = WeatherDaylight.isDay(hour, forecast: forecast, location: location)
        return VStack(spacing: 5) {
            Text(WeatherHourLabel.text(for: hour.timestamp, timeZoneIdentifier: forecast.timeZoneIdentifier))
                .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
            Image(systemName: WeatherCode.symbol(hour.weatherCode, isDay: isDay))
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
        .accessibilityValue(WeatherCode.description(hour.weatherCode) + (isDay ? "" : ", night"))
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
            // A forecast is a provider reading, not an authored edit: it publishes even while saving is disabled.
            let published = store.publishRuntimeReadings(itemID: item.id, in: profileID) { value in
                guard value.weatherLocation?.id == location.id, value.weatherUnit == requestedUnit else { return }
                value.cachedWeatherForecast = result
            }
            if published == .accepted || published == .unchanged { errorMessage = nil }
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

/// Weather copy: short footers; attribution stays visible.
enum WeatherCopy {
    static let attribution = "Weather and places: Open-Meteo · Geocoding data: GeoNames"

    /// Said only when the forecast's hours are not in this Mac's time zone.
    static func timeZoneFooter(forecastTimeZone: String, current: TimeZone = .current, now: Date = .now) -> String? {
        guard let zone = TimeZone(identifier: forecastTimeZone),
              zone.secondsFromGMT(for: now) != current.secondsFromGMT(for: now) else { return nil }
        return "Hours are in \(forecastTimeZone) time."
    }

    /// The Forecast length row exists only for the hourly forecast; elsewhere it would be a dead control.
    static func showsForecastLength(_ layout: WeatherWidgetLayout) -> Bool { layout == .hourlyForecast }
}

/// An hour of the forecast labelled in the user's own hour format: "3 AM" with a 12-hour clock,
/// "03:00" with a 24-hour clock. Never a bare "03".
enum WeatherHourLabel {
    static func text(for date: Date, timeZoneIdentifier: String, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: usesTwelveHourClock(locale) ? "j" : "jmm", options: 0, locale: locale)
        return formatter.string(from: date)
    }

    /// Whether the locale's preferred hour pattern carries a day period (AM/PM).
    static func usesTwelveHourClock(_ locale: Locale) -> Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "").contains("a")
    }
}

/// Whether a forecast hour falls in daylight at the forecast's place, so its glyph shows a sun or a moon.
///
/// Open-Meteo answers `is_day` for the current reading only (the cached hourly model has no day flag), so
/// each hour is derived from the sun's elevation at the city's coordinates: day while the upper limb of the
/// sun is above the horizon with standard refraction (−0.833°), the same sunrise/sunset definition the
/// provider uses. This needs no extra request and no change to the cached forecast.
enum WeatherDaylight {
    static let horizon = -0.833

    static func isDay(_ hour: WeatherHour, forecast: WeatherForecast, location: WeatherLocation?) -> Bool {
        guard let location, location.latitude.isFinite, location.longitude.isFinite else { return forecast.isDay }
        return isDay(at: hour.timestamp, latitude: location.latitude, longitude: location.longitude)
    }

    static func isDay(at date: Date, latitude: Double, longitude: Double) -> Bool {
        solarElevation(at: date, latitude: latitude, longitude: longitude) > horizon
    }

    /// The sun's elevation in degrees (low-precision solar position, accurate to about 0.1° from 1950 to 2050).
    static func solarElevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let radians = Double.pi / 180
        func normalized(_ degrees: Double) -> Double { let value = degrees.truncatingRemainder(dividingBy: 360); return value < 0 ? value + 360 : value }
        let days = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let meanLongitude = normalized(280.460 + 0.9856474 * days)
        let meanAnomaly = normalized(357.528 + 0.9856003 * days) * radians
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * radians
        let obliquity = (23.439 - 0.0000004 * days) * radians
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude)) / radians
        let siderealTime = normalized(280.46061837 + 360.98564736629 * days)
        let hourAngle = (siderealTime + longitude - rightAscension) * radians
        let latitudeRadians = latitude * radians
        let elevation = asin(sin(latitudeRadians) * sin(declination) + cos(latitudeRadians) * cos(declination) * cos(hourAngle))
        return elevation / radians
    }
}

extension Date {
    /// A forecast hour's label in the user's hour format (see `WeatherHourLabel`).
    func formattedTime(in timeZoneIdentifier: String) -> String {
        WeatherHourLabel.text(for: self, timeZoneIdentifier: timeZoneIdentifier)
    }
}

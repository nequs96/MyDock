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
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var errorMessage: String?
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        ZStack {
            tileBackground
            VStack(spacing: 2) {
                if let forecast = configuration.cachedWeatherForecast {
                    Image(systemName: WeatherCode.symbol(forecast.weatherCode, isDay: forecast.isDay))
                        .font(.system(size: 18)).symbolRenderingMode(.multicolor)
                    Text("\(Int(forecast.temperature.rounded()))°")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1)
                    Text(configuration.weatherLocation?.name ?? "Weather")
                        .font(.system(size: 7, weight: .medium)).lineLimit(1).frame(maxWidth: 52)
                } else {
                    Image(systemName: "cloud.sun").font(.system(size: 20)).foregroundStyle(.tint)
                    Text(configuration.weatherLocation == nil ? "Set city" : "Weather")
                        .font(.system(size: 8, weight: .medium)).lineLimit(1).frame(maxWidth: 52)
                }
            }
            .padding(3)
        }
        .frame(width: 54, height: 54)
        .help(tooltip)
        .task(id: requestKey) { await refreshIfConfigured() }
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

    private var backgroundGradient: LinearGradient {
        let colors: [Color] = configuration.weatherBackground == .themed
            ? [Color.cyan.opacity(0.38), Color.blue.opacity(0.24)]
            : [Color.clear, Color.clear]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder private var tileBackground: some View {
        if accessibility.reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .windowBackgroundColor))
        } else if configuration.weatherBackground == .translucent {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(backgroundGradient)
        }
    }

    private func refreshIfConfigured() async {
        guard let location = configuration.weatherLocation else { return }
        do {
            let forecast = try await WeatherService.shared.forecast(for: location, unit: configuration.weatherUnit)
            guard store.state.profiles.first(where: { $0.id == profileID })?.items.contains(where: { $0.id == item.id }) == true else { return }
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                guard value.weatherLocation?.id == location.id, value.weatherUnit == configuration.weatherUnit else { return }
                value.cachedWeatherForecast = forecast
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WeatherPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var searchText = ""
    @State private var isChangingLocation = false
    @State private var searchResults: [WeatherLocation] = []
    @State private var isSearching = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var unitSelection = WeatherTemperatureUnit.celsius.rawValue
    @State private var layoutSelection = WeatherWidgetLayout.current.rawValue
    @State private var forecastHours = 3
    @State private var backgroundSelection = WeatherBackground.themed.rawValue
    @ObservedObject private var accessibility = AccessibilityDisplayState.shared

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var location: WeatherLocation? { configuration.weatherLocation }
    private var forecast: WeatherForecast? { configuration.cachedWeatherForecast }
    private var requestKey: String { "\(location?.id ?? "unset")|\(configuration.weatherUnit.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weather").font(.headline)
                Spacer()
                if location != nil {
                    Button("Refresh") { refresh(force: true) }.disabled(isLoading)
                }
            }

            if let location {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").foregroundStyle(.tint)
                    Text(location.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    Button("Change") {
                        isChangingLocation = true
                        searchText = ""
                        searchResults = []
                    }
                }
            }

            if location == nil || isChangingLocation {
                locationSearchSection
            }

            settingsSection

            if isLoading {
                ProgressView("Loading forecast…").frame(maxWidth: .infinity, minHeight: 90)
            }
            if let forecast { forecastContent(forecast) }
            if let forecast {
                Text("Updated \(forecast.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if let errorMessage {
                Label(forecast == nil ? errorMessage : "Showing saved forecast. \(errorMessage)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Text("Weather and places: Open-Meteo · Geocoding data: GeoNames")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 390).frame(minHeight: 220, alignment: .topLeading)
        .onAppear {
            unitSelection = configuration.weatherUnit.rawValue
            layoutSelection = configuration.weatherLayout.rawValue
            forecastHours = configuration.weatherForecastHours
            backgroundSelection = configuration.weatherBackground.rawValue
        }
        .onChange(of: unitSelection) { rawValue in
            guard let value = WeatherTemperatureUnit(rawValue: rawValue) else { return }
            updateConfiguration { $0.weatherUnit = value }
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
        .onChange(of: item.widgetConfiguration?.weatherUnit) { value in unitSelection = (value ?? .celsius).rawValue }
        .onChange(of: item.widgetConfiguration?.weatherLayout) { value in layoutSelection = (value ?? .current).rawValue }
        .onChange(of: item.widgetConfiguration?.weatherForecastHours) { value in forecastHours = value ?? 3 }
        .onChange(of: item.widgetConfiguration?.weatherBackground) { value in backgroundSelection = (value ?? .themed).rawValue }
        .task(id: requestKey) {
            await refreshIfConfigured()
            for await _ in RefreshScheduler.shared.ticks(every: 10 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfConfigured()
            }
        }
    }

    @ViewBuilder private var locationSearchSection: some View {
        HStack(spacing: 7) {
            TextField("Search for a city", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(search)
            Button("Search", action: search).disabled(isSearching)
        }
        HStack {
            Button("Use Current Location", action: useCurrentLocation)
                .buttonStyle(.bordered)
            Text("Location permission is only requested if you choose this.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        if isSearching { ProgressView("Searching cities…") }
        if !searchResults.isEmpty {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(searchResults) { result in
                        Button { select(result) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.callout.weight(.medium))
                                    Text([result.administrativeArea, result.country].compactMap { $0 }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(.tint)
                            }
                            .padding(7)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 125)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Layout", selection: $layoutSelection) {
                    ForEach(WeatherWidgetLayout.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .frame(maxWidth: 160)
                Picker("Units", selection: $unitSelection) {
                    ForEach(WeatherTemperatureUnit.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .frame(maxWidth: 75)
            }
            HStack {
                Picker("Background", selection: $backgroundSelection) {
                    ForEach(WeatherBackground.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .frame(maxWidth: 150)
                Spacer()
                Stepper(value: $forecastHours, in: 1...6) {
                    Text("\(forecastHours) hours").font(.caption)
                }
                .disabled(configuration.weatherLayout != .hourlyForecast)
                .frame(maxWidth: 160)
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private func forecastContent(_ forecast: WeatherForecast) -> some View {
        Group {
            switch configuration.weatherLayout {
            case .current:
                currentSummary(forecast)
            case .conditions:
                currentSummary(forecast)
                conditionDetails(forecast)
            case .hourlyForecast:
                currentSummary(forecast)
                hourlyList(forecast)
            }
        }
    }

    private func currentSummary(_ forecast: WeatherForecast) -> some View {
        HStack(spacing: 14) {
            Image(systemName: WeatherCode.symbol(forecast.weatherCode, isDay: forecast.isDay))
                .font(.system(size: 42)).symbolRenderingMode(.multicolor).frame(width: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Int(forecast.temperature.rounded()))\(configuration.weatherUnit.title)")
                    .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                Text(WeatherCode.description(forecast.weatherCode)).font(.callout.weight(.medium))
                Text("Feels like \(Int(forecast.apparentTemperature.rounded()))\(configuration.weatherUnit.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(weatherBackground(for: forecast.weatherCode), in: RoundedRectangle(cornerRadius: 12))
    }

    private func conditionDetails(_ forecast: WeatherForecast) -> some View {
        HStack(spacing: 0) {
            detailCell("Humidity", value: "\(forecast.relativeHumidity)%", symbol: "humidity")
            detailCell("Wind", value: "\(Int(forecast.windSpeed.rounded())) km/h", symbol: "wind")
            detailCell("Precipitation", value: "\(forecast.precipitation.formatted(.number.precision(.fractionLength(0...1)))) mm", symbol: "drop")
        }
    }

    private func detailCell(_ title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }

    private func hourlyList(_ forecast: WeatherForecast) -> some View {
        let hours = forecast.hourly.filter { $0.timestamp > .now }.prefix(configuration.weatherForecastHours)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(hours)) { hour in
                    VStack(spacing: 5) {
                        Text(hour.timestamp.formattedTime(in: forecast.timeZoneIdentifier))
                            .font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: WeatherCode.symbol(hour.weatherCode, isDay: true))
                            .font(.system(size: 16)).symbolRenderingMode(.multicolor)
                        Text("\(Int(hour.temperature.rounded()))\(configuration.weatherUnit.title)")
                            .font(.callout.weight(.semibold).monospacedDigit())
                        if let chance = hour.precipitationProbability {
                            Label("\(chance)%", systemImage: "drop.fill").font(.caption2).foregroundStyle(.blue)
                        }
                    }
                    .padding(8)
                    .frame(minWidth: 58)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func weatherBackground(for code: Int) -> some ShapeStyle {
        if accessibility.reduceTransparency { return AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) }
        if configuration.weatherBackground == .translucent { return AnyShapeStyle(.ultraThinMaterial) }
        let color: Color = code >= 95 ? .purple : code >= 51 ? .blue : code >= 3 ? .gray : .orange
        return AnyShapeStyle(LinearGradient(colors: [color.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { errorMessage = WeatherServiceError.invalidSearch.localizedDescription; return }
        isSearching = true
        errorMessage = nil
        Task {
            defer { isSearching = false }
            do { searchResults = try await WeatherService.shared.searchLocations(query) }
            catch { searchResults = []; errorMessage = error.localizedDescription }
        }
    }

    private func select(_ location: WeatherLocation) {
        searchResults = []
        searchText = ""
        errorMessage = nil
        updateConfiguration { value in
            value.weatherLocation = location
            value.cachedWeatherForecast = nil
        }
        isChangingLocation = false
    }

    private func useCurrentLocation() {
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            defer { isLoading = false }
            do { select(try await CurrentLocationService.shared.currentLocation()) }
            catch { errorMessage = error.localizedDescription }
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
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await WeatherService.shared.forecast(for: location, unit: requestedUnit, forceRefresh: force)
            guard configuration.weatherLocation?.id == location.id, configuration.weatherUnit == requestedUnit else { return }
            updateConfiguration { $0.cachedWeatherForecast = result }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateConfiguration(_ update: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: update)
    }
}

private enum WeatherCode {
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

private extension Date {
    func formattedTime(in timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)
        return formatter.string(from: self)
    }
}

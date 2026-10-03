import Foundation

enum WeatherServiceError: LocalizedError {
    case invalidSearch
    case locationNotFound
    case serviceUnavailable
    case malformedResponse
    case locationDenied

    var errorDescription: String? {
        switch self {
        case .invalidSearch: "Enter at least two characters to search for a city."
        case .locationNotFound: "No matching city was found. Try adding a country or region."
        case .serviceUnavailable: "The weather service is unavailable. Check your connection and try again."
        case .malformedResponse: "The weather service returned data MyDock couldn't use."
        case .locationDenied: "Location access is unavailable. You can still search for a city manually."
        }
    }
}

protocol WeatherProvider: Sendable {
    func searchLocations(_ query: String) async throws -> [WeatherLocation]
    func forecast(for location: WeatherLocation, unit: WeatherTemperatureUnit) async throws -> WeatherForecast
}

struct OpenMeteoWeatherProvider: WeatherProvider {
    func searchLocations(_ query: String) async throws -> [WeatherLocation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { throw WeatherServiceError.invalidSearch }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WeatherServiceError.invalidSearch }
        let (data, _) = try await Self.fetch(url)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        let results = response.results ?? []
        guard !results.isEmpty else { throw WeatherServiceError.locationNotFound }
        return results.map { result in
            WeatherLocation(id: "geonames-\(result.id)",
                            name: result.name,
                            administrativeArea: result.admin1,
                            country: result.country,
                            latitude: result.latitude,
                            longitude: result.longitude,
                            timeZoneIdentifier: result.timezone ?? TimeZone.current.identifier)
        }
    }

    func forecast(for location: WeatherLocation, unit: WeatherTemperatureUnit) async throws -> WeatherForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        guard let url = components?.url else { throw WeatherServiceError.malformedResponse }
        let (data, _) = try await Self.fetch(url)
        return try Self.decodeForecast(data, location: location, fetchedAt: .now)
    }

    static func decodeForecast(_ data: Data, location: WeatherLocation, fetchedAt: Date = .now) throws -> WeatherForecast {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        // Finite-but-absurd readings (either unit) are malformed data, not something to format or cache.
        let temperatureRange = -500.0...500.0
        guard temperatureRange.contains(response.current.temperature),
              temperatureRange.contains(response.current.apparentTemperature),
              (0.0...1_000.0).contains(response.current.windSpeed),
              response.current.precipitation.isFinite, (0.0...10_000.0).contains(response.current.precipitation),
              (0...100).contains(response.current.relativeHumidity),
              response.hourly.temperature.allSatisfy({ temperatureRange.contains($0) }),
              response.hourly.time.allSatisfy({ $0.isFinite && abs($0) < 4_102_444_800 }) else {
            throw WeatherServiceError.malformedResponse
        }
        let hours = min(response.hourly.time.count,
                        min(response.hourly.temperature.count, response.hourly.weatherCode.count))
        let hourly = (0..<hours).map { index in
            let precipitationProbability = response.hourly.precipitationProbability.flatMap { values in
                index < values.count ? values[index] : nil
            }
            return WeatherHour(timestamp: Date(timeIntervalSince1970: response.hourly.time[index]),
                               temperature: response.hourly.temperature[index],
                               precipitationProbability: precipitationProbability,
                               weatherCode: response.hourly.weatherCode[index])
        }
        guard response.current.temperature.isFinite,
              response.current.apparentTemperature.isFinite,
              response.current.windSpeed.isFinite else { throw WeatherServiceError.malformedResponse }
        return WeatherForecast(temperature: response.current.temperature,
                              apparentTemperature: response.current.apparentTemperature,
                              relativeHumidity: response.current.relativeHumidity,
                              precipitation: response.current.precipitation,
                              windSpeed: response.current.windSpeed,
                              weatherCode: response.current.weatherCode,
                              isDay: response.current.isDay == 1,
                              fetchedAt: fetchedAt,
                              timeZoneIdentifier: response.timezone ?? location.timeZoneIdentifier,
                              hourly: hourly)
    }

    private static func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        guard let host = url.host?.lowercased(), host == "api.open-meteo.com" || host == "geocoding-api.open-meteo.com" else {
            throw WeatherServiceError.serviceUnavailable
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MyDock weather widget", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw WeatherServiceError.serviceUnavailable }
            guard (200..<300).contains(response.statusCode) else { throw WeatherServiceError.serviceUnavailable }
            return (data, response)
        } catch let error as WeatherServiceError {
            throw error
        } catch {
            throw WeatherServiceError.serviceUnavailable
        }
    }
}

actor WeatherService {
    private struct ForecastKey: Hashable {
        var locationID: String
        var latitude: Double
        var longitude: Double
        var unit: WeatherTemperatureUnit
    }

    private struct CachedForecast {
        var value: WeatherForecast
        var expiresAt: Date
    }

    static let shared = WeatherService(provider: OpenMeteoWeatherProvider())

    private let provider: any WeatherProvider
    private let maximumCachedForecasts: Int
    private var cache: [ForecastKey: CachedForecast] = [:]
    private var inFlight: [ForecastKey: Task<WeatherForecast, Error>] = [:]

    init(provider: any WeatherProvider, maximumCachedForecasts: Int = 128) {
        self.provider = provider
        self.maximumCachedForecasts = max(1, maximumCachedForecasts)
    }

    func searchLocations(_ query: String) async throws -> [WeatherLocation] {
        try await provider.searchLocations(query)
    }

    func forecast(for location: WeatherLocation,
                  unit: WeatherTemperatureUnit,
                  forceRefresh: Bool = false) async throws -> WeatherForecast {
        let key = ForecastKey(locationID: location.id, latitude: location.latitude,
                              longitude: location.longitude, unit: unit)
        if !forceRefresh, let cached = cache[key], cached.expiresAt > .now { return cached.value }
        if let task = inFlight[key] { return try await task.value }
        let provider = self.provider
        let task = Task.detached(priority: .utility) { try await provider.forecast(for: location, unit: unit) }
        inFlight[key] = task
        do {
            let value = try await task.value
            cache = cache.filter { $0.value.expiresAt > .now }
            cache[key] = CachedForecast(value: value, expiresAt: .now.addingTimeInterval(10 * 60))
            if cache.count > maximumCachedForecasts,
               let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                cache[oldest] = nil
            }
            inFlight.removeValue(forKey: key)
            return value
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }
}

private struct GeocodingResponse: Decodable {
    var results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
    var id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String?
    var admin1: String?
    var timezone: String?
}

private struct ForecastResponse: Decodable {
    var current: CurrentPayload
    var hourly: HourlyPayload
    var timezone: String?
}

private struct CurrentPayload: Decodable {
    var temperature: Double
    var relativeHumidity: Int
    var apparentTemperature: Double
    var precipitation: Double
    var weatherCode: Int
    var isDay: Int
    var windSpeed: Double

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case relativeHumidity = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitation
        case weatherCode = "weather_code"
        case isDay = "is_day"
        case windSpeed = "wind_speed_10m"
    }
}

private struct HourlyPayload: Decodable {
    var time: [TimeInterval]
    var temperature: [Double]
    var precipitationProbability: [Int]?
    var weatherCode: [Int]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
    }
}

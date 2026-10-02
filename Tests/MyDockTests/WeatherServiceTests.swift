import Foundation
import Testing
@testable import MyDock

private actor CountingWeatherProvider: WeatherProvider {
    private(set) var forecastCalls = 0

    func searchLocations(_ query: String) async throws -> [WeatherLocation] { [] }

    func forecast(for location: WeatherLocation, unit: WeatherTemperatureUnit) async throws -> WeatherForecast {
        forecastCalls += 1
        return WeatherForecast(temperature: location.latitude,
                               apparentTemperature: location.latitude,
                               relativeHumidity: 50,
                               precipitation: 0,
                               windSpeed: 0,
                               weatherCode: 0,
                               isDay: true,
                               fetchedAt: .now,
                               timeZoneIdentifier: location.timeZoneIdentifier,
                               hourly: [])
    }
}

struct WeatherServiceTests {
    @Test func forecastCacheEvictsOldLocationsWhileRetainingTheNewest() async throws {
        let provider = CountingWeatherProvider()
        let service = WeatherService(provider: provider, maximumCachedForecasts: 1)
        let first = WeatherLocation(id: "first", name: "First", administrativeArea: nil,
                                    country: nil, latitude: 52, longitude: 21, timeZoneIdentifier: "Europe/Warsaw")
        var second = first
        second.id = "second"
        _ = try await service.forecast(for: first, unit: .celsius)
        try await Task.sleep(for: .milliseconds(1))
        _ = try await service.forecast(for: second, unit: .celsius)
        _ = try await service.forecast(for: second, unit: .celsius)
        #expect(await provider.forecastCalls == 2)
        _ = try await service.forecast(for: first, unit: .celsius)
        #expect(await provider.forecastCalls == 3)
    }

    @Test func changingWeatherUnitsClearsTheOldNumberBeforeRefresh() {
        var configuration = WidgetConfiguration()
        let saved = WeatherForecast(temperature: 22, apparentTemperature: 22,
                                    relativeHumidity: 50, precipitation: 0, windSpeed: 0,
                                    weatherCode: 0, isDay: true, fetchedAt: .now,
                                    timeZoneIdentifier: "Europe/Warsaw", hourly: [])
        configuration.cachedWeatherForecast = saved

        configuration.selectWeatherUnit(.celsius)
        #expect(configuration.cachedWeatherForecast == saved)
        configuration.selectWeatherUnit(.fahrenheit)
        #expect(configuration.weatherUnit == .fahrenheit)
        #expect(configuration.cachedWeatherForecast == nil)
    }

    @Test func forecastCacheSeparatesCoordinatesUnderTheSameLocationID() async throws {
        let provider = CountingWeatherProvider()
        let service = WeatherService(provider: provider)
        let first = WeatherLocation(id: "current", name: "Current location", administrativeArea: nil,
                                    country: nil, latitude: 52.20, longitude: 21.00,
                                    timeZoneIdentifier: "Europe/Warsaw")
        var moved = first
        moved.latitude = 52.21

        let initial = try await service.forecast(for: first, unit: .celsius)
        let afterMove = try await service.forecast(for: moved, unit: .celsius)
        let cachedInitial = try await service.forecast(for: first, unit: .celsius)

        #expect(initial.temperature == 52.20)
        #expect(afterMove.temperature == 52.21)
        #expect(cachedInitial.temperature == initial.temperature)
        #expect(await provider.forecastCalls == 2)
    }

    @Test func shortPrecipitationArrayDoesNotDiscardValidForecastHours() throws {
        let payload = Data(#"{"current":{"temperature_2m":18,"relative_humidity_2m":50,"apparent_temperature":18,"precipitation":0,"weather_code":1,"is_day":1,"wind_speed_10m":4},"hourly":{"time":[1727193600,1727197200],"temperature_2m":[18,19],"precipitation_probability":[10],"weather_code":[1,2]},"timezone":"Europe/Warsaw"}"#.utf8)
        let location = WeatherLocation(id: "city", name: "Warsaw", administrativeArea: nil,
                                       country: "Poland", latitude: 52.23, longitude: 21.01,
                                       timeZoneIdentifier: "Europe/Warsaw")
        let forecast = try OpenMeteoWeatherProvider.decodeForecast(payload, location: location)

        #expect(forecast.hourly.count == 2)
        #expect(forecast.hourly[0].precipitationProbability == 10)
        #expect(forecast.hourly[1].precipitationProbability == nil)
    }
}

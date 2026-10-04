import Foundation
import IOKit.ps
import Testing
@testable import MyDock

@MainActor
struct ProductVisualFixTests {
    @Test func forecastColumnsReserveTheCurrentTemperatureBeforeAddingHours() {
        for temperature in ["21°", "-21°", "-150°", "302°"] {
            for width in stride(from: 90.0, through: 220.0, by: 1) {
                let columns = WeatherForecastFaceLayout.columnCount(width: width, temperatureText: temperature, availableHours: 6)
                #expect((0...3).contains(columns))
                if columns > 0 {
                    let used = 18 + WeatherForecastFaceLayout.primaryWidth(temperatureText: temperature) + Double(columns) * 37
                    #expect(used <= width)
                }
            }
        }
        #expect(WeatherForecastFaceLayout.columnCount(width: 186, temperatureText: "21°", availableHours: 6) == 3)
        #expect(WeatherForecastFaceLayout.columnCount(width: 186, temperatureText: "-150°", availableHours: 6) == 2)
        #expect(WeatherForecastFaceLayout.columnCount(width: 120, temperatureText: "21°", availableHours: 6) == 1)
        #expect(WeatherForecastFaceLayout.columnCount(width: 90, temperatureText: "21°", availableHours: 6) == 0)
    }

    @Test func forecastColumnsRespectMissingOrLimitedHourlyData() {
        #expect(WeatherForecastFaceLayout.columnCount(width: 186, temperatureText: "21°", availableHours: 0) == 0)
        #expect(WeatherForecastFaceLayout.columnCount(width: 186, temperatureText: "21°", availableHours: 1) == 1)
        #expect(WeatherForecastFaceLayout.columnCount(width: 54, temperatureText: "-150°", availableHours: 6) == 0)
    }

    @Test func shortTickersPreserveOrdinarySymbolsAndBoundLongSymbols() {
        for ticker in ["AAPL", "BRK-B", "EURUSD"] {
            #expect(FinancialFacePresentation.shortTicker(ticker) == ticker)
        }
        let long = "VERYLONG-TICKER"
        let shortened = FinancialFacePresentation.shortTicker(long)
        #expect(shortened.count == 6)
        #expect(shortened.hasPrefix(String(long.prefix(5))))
        #expect(shortened.hasSuffix("+"))
    }

    @Test func internalBatteryDisplayNamesKeepSourceIdentityAndPeripheralNames() throws {
        let description: [String: Any] = [
            kIOPSNameKey as String: "InternalBattery-0",
            kIOPSCurrentCapacityKey as String: 98,
            kIOPSMaxCapacityKey as String: 100,
            kIOPSTypeKey as String: kIOPSInternalBatteryType as String
        ]
        let reading = try #require(BatteryReader.reading(from: description))
        #expect(reading.displayName == "Mac battery")
        #expect(reading.name == "InternalBattery-0")
        #expect(reading.id == "InternalBattery-0-true")
        #expect(reading.percentage == 98)
        let peripheral = BatteryReading(name: "Jakub’s AirPods", percentage: 92, isCharging: true, isInternal: false)
        #expect(peripheral.displayName == peripheral.name)
    }

    @Test func compactWorldClockDateUsesTheSelectedZonesCalendarDay() throws {
        let date = Date(timeIntervalSince1970: 1_791_072_000) // 4 October 2026, 00:00 UTC
        let west = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let east = try #require(TimeZone(secondsFromGMT: 2 * 3600))
        #expect(WorldClockFaceDateFormatter.text(date, timeZone: west) != WorldClockFaceDateFormatter.text(date, timeZone: east))
        #expect(WorldClockFaceDateFormatter.text(date, timeZone: east).count < formattedDate(date, timeZone: east).count)
    }
}

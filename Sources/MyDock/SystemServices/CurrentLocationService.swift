@preconcurrency import CoreLocation
import Foundation

@MainActor
final class CurrentLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = CurrentLocationService()

    private let manager: CLLocationManager
    private var pendingContinuation: CheckedContinuation<WeatherLocation, Error>?
    private var pendingRequestID: UUID?
    private var didRequestLocation = false

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> WeatherLocation {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard pendingContinuation == nil else { throw WeatherServiceError.serviceUnavailable }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingContinuation = continuation
                pendingRequestID = requestID
                switch manager.authorizationStatus {
                case .authorizedAlways, .authorizedWhenInUse:
                    requestLocationIfNeeded()
                case .notDetermined:
                    manager.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    finish(.failure(WeatherServiceError.locationDenied))
                @unknown default:
                    finish(.failure(WeatherServiceError.locationDenied))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelRequest(id: requestID) }
        }
    }

    private func cancelRequest(id: UUID) {
        guard pendingRequestID == id else { return }
        manager.stopUpdatingLocation()
        finish(.failure(CancellationError()))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingContinuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationIfNeeded()
        case .denied, .restricted:
            finish(.failure(WeatherServiceError.locationDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(WeatherServiceError.locationDenied))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(WeatherServiceError.locationDenied))
            return
        }
        let coordinate = location.coordinate
        finish(.success(WeatherLocation(id: "current-\(coordinate.latitude.rounded(toPlaces: 3))-\(coordinate.longitude.rounded(toPlaces: 3))",
                                        name: "Current location",
                                        administrativeArea: nil,
                                        country: nil,
                                        latitude: coordinate.latitude,
                                        longitude: coordinate.longitude,
                                        timeZoneIdentifier: TimeZone.current.identifier)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<WeatherLocation, Error>) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        didRequestLocation = false
        continuation.resume(with: result)
    }

    private func requestLocationIfNeeded() {
        guard !didRequestLocation else { return }
        didRequestLocation = true
        manager.requestLocation()
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

@preconcurrency import CoreLocation
import Foundation

enum CurrentLocationError: LocalizedError, Equatable {
    case unavailable
    case timedOut
    case staleOrInaccurate
    case busy
    case servicesDisabled

    var errorDescription: String? {
        switch self {
        case .unavailable: "Your current location could not be determined. You can still search for a city manually."
        case .timedOut: "Your location was not available in time. Check Location Services, or search for a city manually."
        case .staleOrInaccurate: "MyDock could not get a recent, accurate location fix. Try again, or search for a city manually."
        case .busy: "A location request is already in progress."
        case .servicesDisabled: "Location Services is off. Turn it on in System Settings → Privacy & Security → Location Services, or search for a city manually."
        }
    }
}

/// Decides whether a delivered fix is fresh and precise enough for a city-level forecast.
enum LocationFixPolicy {
    static let maximumAge: TimeInterval = 10 * 60
    static let maximumHorizontalAccuracy: Double = 5_000
    /// Overall wait including a permission prompt.
    static let requestDeadline: TimeInterval = 45

    enum Verdict: Equatable { case accept, stale, inaccurate }

    static func evaluate(timestamp: Date, horizontalAccuracy: Double, now: Date = .now) -> Verdict {
        guard horizontalAccuracy.isFinite, horizontalAccuracy >= 0, horizontalAccuracy <= maximumHorizontalAccuracy else {
            return .inaccurate
        }
        // Future timestamps (clock skew) are treated as fresh; only genuinely old fixes are rejected.
        return now.timeIntervalSince(timestamp) > maximumAge ? .stale : .accept
    }
}

@MainActor
final class CurrentLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = CurrentLocationService()

    private let manager: CLLocationManager
    private var pendingContinuation: CheckedContinuation<WeatherLocation, Error>?
    private var pendingRequestID: UUID?
    private var didRequestLocation = false
    private var deadlineTask: Task<Void, Never>?

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> WeatherLocation {
        try AppRuntimeEnvironment.requireNativeEffects()
        // With Location Services off system-wide no prompt appears, so fail now rather than at the deadline.
        // Apple notes this check can block, so it runs off the main actor.
        let servicesEnabled = await Task.detached(priority: .userInitiated) { CLLocationManager.locationServicesEnabled() }.value
        guard servicesEnabled else { throw CurrentLocationError.servicesDisabled }
        guard pendingContinuation == nil else { throw CurrentLocationError.busy }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingContinuation = continuation
                pendingRequestID = requestID
                deadlineTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(LocationFixPolicy.requestDeadline))
                    guard !Task.isCancelled else { return }
                    self?.expireRequest(id: requestID)
                }
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

    private func expireRequest(id: UUID) {
        guard pendingRequestID == id else { return }
        manager.stopUpdatingLocation()
        finish(.failure(CurrentLocationError.timedOut))
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
        guard pendingContinuation != nil else { return }
        let now = Date()
        let verdicts = locations.map { LocationFixPolicy.evaluate(timestamp: $0.timestamp,
                                                                   horizontalAccuracy: $0.horizontalAccuracy,
                                                                   now: now) }
        guard let index = locations.indices.last(where: { verdicts[$0] == .accept }) else {
            finish(.failure(locations.isEmpty ? CurrentLocationError.unavailable : CurrentLocationError.staleOrInaccurate))
            return
        }
        let coordinate = locations[index].coordinate
        finish(.success(WeatherLocation(id: "current-\(coordinate.latitude.rounded(toPlaces: 3))-\(coordinate.longitude.rounded(toPlaces: 3))",
                                        name: "Current location",
                                        administrativeArea: nil,
                                        country: nil,
                                        latitude: coordinate.latitude,
                                        longitude: coordinate.longitude,
                                        timeZoneIdentifier: TimeZone.current.identifier)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            finish(.failure(WeatherServiceError.locationDenied))
        } else {
            finish(.failure(CurrentLocationError.unavailable))
        }
    }

    private func finish(_ result: Result<WeatherLocation, Error>) {
        guard let continuation = pendingContinuation else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
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

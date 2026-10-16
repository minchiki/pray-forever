import CoreLocation

/// Одноразовое определение местоположения + название города.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Failure: Error { case denied, unavailable }

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLocating = false

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> SavedLocation {
        isLocating = true
        defer { isLocating = false }

        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw Failure.denied
        }
        continuation?.resume(throwing: Failure.unavailable)
        let location: CLLocation = try await withCheckedThrowingContinuation { cont in
            continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return SavedLocation(latitude: location.coordinate.latitude,
                             longitude: location.coordinate.longitude,
                             name: placemark?.locality ?? placemark?.administrativeArea)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.continuation != nil { self.manager.requestLocation() }
            case .denied, .restricted:
                self.finish(.failure(Failure.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }
}

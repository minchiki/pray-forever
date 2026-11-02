import MapKit
import SwiftUI

/// Ручной выбор места: поиск города, ввод координат или текущая геолокация.
struct LocationPickerView: View {
    @EnvironmentObject private var coordinator: AlarmCoordinator
    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var location = AlarmCoordinator.shared.location
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var pendingChange: GuardedChange?

    private static let searchDebounce: UInt64 = 400_000_000

    var body: some View {
        Form {
            currentSection
            searchSection
            coordinatesSection
        }
        .navigationTitle(Text("settings.location"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fillCoordinates)
        .guardedChallenge($pendingChange)
    }

    // MARK: - Sections

    private var currentSection: some View {
        Section {
            HStack {
                Text(store.settings.location?.name ?? String(localized: "settings.location.none"))
                Spacer()
                if let loc = store.settings.location {
                    Text(String(format: "%.4f, %.4f", loc.latitude, loc.longitude))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task {
                    if let current = await coordinator.locateCurrent() {
                        apply(current, dismissAfter: false)
                    }
                }
            } label: {
                HStack {
                    Label("location.useCurrent", systemImage: "location.fill")
                    Spacer()
                    if location.isLocating { ProgressView() }
                }
            }
            .disabled(location.isLocating)
            if let error = coordinator.locationError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("location.current")
        }
    }

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("location.search.placeholder", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { search(immediately: true) }
                    .onChange(of: query) { _ in search(immediately: false) }
                if isSearching { ProgressView() }
            }
            if let searchError {
                Text(searchError).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(results, id: \.self) { item in
                Button { select(item) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "—").foregroundStyle(.primary)
                        if let subtitle = Self.subtitle(for: item) {
                            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("location.search")
        }
    }

    private var coordinatesSection: some View {
        Section {
            TextField("location.latitude", text: $latitudeText)
                .keyboardType(.numbersAndPunctuation)
            TextField("location.longitude", text: $longitudeText)
                .keyboardType(.numbersAndPunctuation)
            Button("location.coordinates.save", action: saveCoordinates)
                .disabled(Self.parseCoordinates(latitudeText, longitudeText) == nil)
        } header: {
            Text("location.coordinates")
        } footer: {
            Text("location.coordinates.footer")
        }
    }

    // MARK: - Actions

    private func search(immediately: Bool) {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            searchError = nil
            return
        }
        searchTask = Task {
            if !immediately { try? await Task.sleep(nanoseconds: Self.searchDebounce) }
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = [.address, .pointOfInterest]
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = Array(response.mapItems.prefix(10))
                searchError = results.isEmpty ? String(localized: "location.search.empty") : nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchError = String(localized: "location.search.error")
            }
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        apply(SavedLocation(latitude: coordinate.latitude, longitude: coordinate.longitude,
                            name: item.placemark.locality ?? item.name))
    }

    private func saveCoordinates() {
        guard let (lat, lon) = Self.parseCoordinates(latitudeText, longitudeText) else { return }
        apply(SavedLocation(latitude: lat, longitude: lon, name: nil))
    }

    /// Другое место сдвигает время намаза, поэтому рядом с будильником — только через испытание.
    private func apply(_ newLocation: SavedLocation, dismissAfter: Bool = true) {
        let proposed = store.settings.with { $0.location = newLocation }
        let weakening = AlarmPolicy.weakens(proposed, comparedTo: store.settings)
        coordinator.perform(weakening: weakening, pending: $pendingChange) {
            coordinator.locationError = nil
            store.update { $0.location = newLocation }
            if dismissAfter {
                dismiss()
            } else {
                fillCoordinates()
            }
        }
    }

    private func fillCoordinates() {
        guard let loc = store.settings.location else { return }
        latitudeText = String(format: "%.4f", loc.latitude)
        longitudeText = String(format: "%.4f", loc.longitude)
    }

    // MARK: - Helpers

    static func parseCoordinates(_ lat: String, _ lon: String) -> (Double, Double)? {
        func parse(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        guard let latitude = parse(lat), let longitude = parse(lon),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return (latitude, longitude)
    }

    private static func subtitle(for item: MKMapItem) -> String? {
        let parts = [item.placemark.administrativeArea, item.placemark.country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

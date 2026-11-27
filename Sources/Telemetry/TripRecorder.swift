import Foundation
import SwiftData
import CoreLocation
import Combine

// MARK: - Trip Recorder
// Accumulates telemetry samples into a trip, integrates energy, and persists to SwiftData.

@MainActor
final class TripRecorder: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRecording = false
    @Published private(set) var currentTrip: TripRecord?

    // Live stats
    @Published private(set) var tripDistanceKm: Double = 0
    @Published private(set) var tripDurationSeconds: Double = 0
    @Published private(set) var tripEnergyKWh: Double = 0
    @Published private(set) var tripCostEUR: Double = 0
    @Published private(set) var currentConsumptionKWhPer100Km: Double?
    @Published private(set) var maxSpeedKmh: Double = 0

    // MARK: - Private

    private var samples: [TelemetrySample] = []
    private var cancellables = Set<AnyCancellable>()
    private weak var modelContext: ModelContext?
    private var tariffProfile: BulgarianTariffProfile
    private var tripTimer: Timer?
    private var tripStart: Date?
    private var lastLocation: CLLocation?
    private var firstLocation: CLLocation?
    private var lastValidLocation: CLLocation?
    private var isStopped = false
    private var stopStartedAt: Date?
    private var stopCount = 0
    private var stopTimes: [Date] = []
    private var unsavedRawFrames = 0

    // MARK: - Init

    init(modelContext: ModelContext, tariffProfile: BulgarianTariffProfile = .load()) {
        self.modelContext = modelContext
        self.tariffProfile = tariffProfile
    }

    // MARK: - Bindings

    func bind(session: OBDSession, locationManager: LocationManager) {
        // Telemetry samples
        session.sampleUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                self?.ingestSample(sample)
            }
            .store(in: &cancellables)

        // Raw frames
        session.rawResponses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                // Preserve every raw response, including ELM initialisation and
                // discovery frames before a trip starts. Associate it with the
                // current trip when one is active.
                let tagged = RawOBDFrame(
                    request: frame.request,
                    response: frame.response,
                    tripID: self.isRecording ? self.currentTrip?.id : nil
                )
                self.modelContext?.insert(tagged)
                self.unsavedRawFrames += 1
                if self.unsavedRawFrames >= 25 {
                    self.flushRawFrames()
                }
            }
            .store(in: &cancellables)

        // GPS location updates
        locationManager.$location
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] loc in
                self?.ingestLocation(loc)
            }
            .store(in: &cancellables)
    }

    // MARK: - Start / Stop

    func startTrip() {
        guard !isRecording else { return }
        let record = TripRecord(startDate: .now)
        modelContext?.insert(record)
        try? modelContext?.save()

        currentTrip = record
        samples.removeAll()
        tripDistanceKm = 0
        tripDurationSeconds = 0
        tripEnergyKWh = 0
        tripCostEUR = 0
        maxSpeedKmh = 0
        currentConsumptionKWhPer100Km = nil
        firstLocation = nil
        lastValidLocation = nil
        isStopped = false
        stopStartedAt = nil
        stopCount = 0
        stopTimes.removeAll()
        tripStart = .now
        isRecording = true

        tripTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickTimer()
            }
        }
    }

    func stopTrip() {
        guard isRecording, let record = currentTrip else { return }
        isRecording = false
        tripTimer?.invalidate()
        tripTimer = nil

        if isStopped, let started = stopStartedAt, Date.now.timeIntervalSince(started) >= 60 {
            stopCount += 1
            stopTimes.append(started)
        }

        // Finalise record
        record.endDate = .now
        record.distanceKm = tripDistanceKm
        record.durationSeconds = tripDurationSeconds
        record.averageSpeedKmh = EnergyCalculator.averageSpeedKmh(distanceKm: tripDistanceKm, durationSeconds: tripDurationSeconds) ?? 0
        record.maxSpeedKmh = maxSpeedKmh
        record.energyKWh = tripEnergyKWh
        record.consumptionKWhPer100Km = EnergyCalculator.consumptionKWhPer100Km(energyKWh: tripEnergyKWh, distanceKm: tripDistanceKm)
        record.costEUR = tripCostEUR
        record.stopCount = stopCount
        record.stopSummary = stopTimes.isEmpty
            ? nil
            : stopTimes.map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: ", ")
        record.startLatitude = firstLocation?.coordinate.latitude
        record.startLongitude = firstLocation?.coordinate.longitude
        record.endLatitude = lastValidLocation?.coordinate.latitude
        record.endLongitude = lastValidLocation?.coordinate.longitude
        record.summary = TripSummaryGenerator.summary(for: record)

        flushRawFrames()
        try? modelContext?.save()
        currentTrip = record

        resolvePlaces(for: record)
    }

    // MARK: - Ingestion

    func ingestSample(_ sample: TelemetrySample) {
        guard isRecording else { return }

        // Apply GPS speed if OBD speed is unavailable
        var enriched = sample
        if enriched.speedKmh == nil {
            if let loc = lastLocation, loc.speed >= 0 {
                enriched.gpsSpeedKmh = loc.speed * 3.6
            }
        }

        samples.append(enriched)

        // Update max speed
        if let speed = enriched.effectiveSpeedKmh {
            maxSpeedKmh = max(maxSpeedKmh, speed)
        }

        // Power-based energy integration (Rule 5). Signed power: positive is
        // discharge, negative is regen. Regen reduces net trip energy but is
        // never billed as negative cost.
        if samples.count >= 2 {
            let previous = samples[samples.count - 2]
            let current = samples[samples.count - 1]
            let deltaTime = current.timestamp.timeIntervalSince(previous.timestamp)
            if deltaTime > 0, deltaTime < 10 {  // Ignore large gaps (e.g. resume after background)
                if let power = previous.batteryPowerKW {
                    let deltaEnergy = power * deltaTime / 3_600.0
                    tripEnergyKWh = max(0, tripEnergyKWh + deltaEnergy)

                    let billableEnergy = max(0, deltaEnergy)
                    if billableEnergy > 0 {
                        tripCostEUR += BulgarianTariffEngine.costForInterval(
                            energyKWh: billableEnergy,
                            start: previous.timestamp,
                            end: current.timestamp,
                            profile: tariffProfile
                        )
                    }
                }
            }
        }

        // Rolling consumption
        if tripDistanceKm > 0 {
            currentConsumptionKWhPer100Km = EnergyCalculator.consumptionKWhPer100Km(
                energyKWh: tripEnergyKWh,
                distanceKm: tripDistanceKm
            )
        }
    }

    private func ingestLocation(_ location: CLLocation) {
        guard isRecording else {
            lastLocation = location
            return
        }

        // Ignore fixes that are too inaccurate to trust.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }

        if firstLocation == nil {
            firstLocation = location
        }
        lastValidLocation = location

        if let previous = lastLocation {
            let delta = location.distance(from: previous) / 1_000.0
            if delta < 0.5 {
                tripDistanceKm += delta
            }
        }
        lastLocation = location

        // A stop counts when the car stays below ~3 km/h for at least a minute.
        let speed = location.speed
        if speed >= 0, speed < 0.8 {
            if !isStopped {
                isStopped = true
                stopStartedAt = .now
            }
        } else if speed > 1.5, isStopped {
            if let started = stopStartedAt, Date.now.timeIntervalSince(started) >= 60 {
                stopCount += 1
                stopTimes.append(started)
            }
            isStopped = false
            stopStartedAt = nil
        }
    }

    private func resolvePlaces(for record: TripRecord) {
        guard let startLatitude = record.startLatitude,
              let startLongitude = record.startLongitude,
              let endLatitude = record.endLatitude,
              let endLongitude = record.endLongitude else { return }

        let geocoder = CLGeocoder()
        let group = DispatchGroup()
        var startName: String?
        var endName: String?

        group.enter()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: startLatitude, longitude: startLongitude)) { placemarks, _ in
            startName = Self.placeName(from: placemarks?.first)
            group.leave()
        }

        group.enter()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: endLatitude, longitude: endLongitude)) { placemarks, _ in
            endName = Self.placeName(from: placemarks?.first)
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            record.startPlace = startName
            record.endPlace = endName
            record.summary = TripSummaryGenerator.summary(for: record)
            try? self.modelContext?.save()
        }
    }

    private static func placeName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name
    }

    private func tickTimer() {
        guard isRecording, let start = tripStart else { return }
        tripDurationSeconds = Date.now.timeIntervalSince(start)
    }

    // MARK: - Persistence

    private func flushRawFrames() {
        guard unsavedRawFrames > 0 else { return }
        try? modelContext?.save()
        unsavedRawFrames = 0
    }

    // MARK: - Tariff update

    func updateTariff(_ profile: BulgarianTariffProfile) {
        tariffProfile = profile
        profile.save()
    }
}

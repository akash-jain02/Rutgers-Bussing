import Foundation
import SwiftUI
import WatchConnectivity

struct Transfer: Codable {
    var trip: SavedTrip?
    var snapshot: Snapshot?
    var demo: Bool
    var journeyPreview: JourneyPreview? = nil
}

enum DemoScenario: String, CaseIterable, Identifiable {
    case normal = "Normal", close = "Next bus too close", delayed = "Delayed", missing = "No predictions", stale = "Stale data", final = "Final scheduled bus"
    var id: String { rawValue }
}

@MainActor
final class TripStore: NSObject, ObservableObject {
    @Published var journeyPreview: JourneyPreview?
    @Published var trip: SavedTrip?
    @Published var snapshot: Snapshot?
    @Published var catalog: [Route] = []
    @Published var demo = true
    @Published var endpoint = "http://localhost:8000"
    @Published var scenario: DemoScenario = .normal
    @Published var error: String?
    @Published var loading = false
    @Published var syncNote: String?
    private var session: WCSession?
    private var generation = 0
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
    static let demoRoutes = [Route(id: "demo-lx", name: "LX · Demo", stops: [Stop(id: "demo-yard", name: "The Yard · Demo"), Stop(id: "demo-livi", name: "Livingston Student Center · Demo")]), Route(id: "demo-h", name: "H · Demo", stops: [Stop(id: "demo-busch", name: "Busch Student Center · Demo")])]

    override init() {
        super.init()
        endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? endpoint
        if let data = UserDefaults.standard.data(forKey: "trip-state"), let state = try? Self.decoder.decode(Transfer.self, from: data) {
            trip = state.trip; snapshot = state.snapshot; demo = state.demo; journeyPreview = state.journeyPreview
        }
        if WCSession.isSupported() {
            session = WCSession.default; session?.delegate = self; session?.activate()
        }
    }
    private func persist() {
        let state = Transfer(trip: trip, snapshot: snapshot, demo: demo, journeyPreview: journeyPreview)
        if let data = try? Self.encoder.encode(state) { UserDefaults.standard.set(data, forKey: "trip-state") }
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
    }
    func publishToWatch() {
        persist()
        #if os(iOS)
        guard let session, session.activationState == .activated else { return }
        guard let data = try? Self.encoder.encode(Transfer(trip: trip, snapshot: snapshot, demo: demo, journeyPreview: journeyPreview)) else { return }
        do { try session.updateApplicationContext(["state": data]); syncNote = nil }
        catch { syncNote = "Watch sync pending. Open both apps to reconnect." }
        #endif
    }
    func configure(demo: Bool, endpoint: String) async {
        generation += 1
        self.demo = demo; self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        trip = nil; snapshot = nil; catalog = []; error = nil
        publishToWatch()
        await loadCatalog()
    }
    func save(_ value: SavedTrip) async {
        generation += 1; trip = value; snapshot = nil; error = nil
        publishToWatch()
        await refresh()
    }
    private func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var parts = URLComponents(string: endpoint), let scheme = parts.scheme, ["http", "https"].contains(scheme), parts.host != nil else { throw URLError(.badURL) }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path
        if !parts.path.hasPrefix("/") { parts.path = "/" + parts.path }
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw URLError(.badURL) }
        return url
    }
    private func request<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        var request = URLRequest(url: url); request.timeoutInterval = 35; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decoder.decode(type, from: data)
    }
    func loadCatalog() async {
        let revision = generation
        if demo { catalog = Self.demoRoutes; return }
        do {
            let routes = try await request([Route].self, url: url("catalog"))
            guard generation == revision else { return }
            catalog = routes; error = nil
        } catch { if generation == revision { self.error = "Cannot load routes. Check your backend address and connection." } }
    }
    func refresh() async {
        #if os(watchOS)
        guard let session, session.isReachable else { error = "Open the iPhone app to refresh. Saved data expires after 90 seconds."; return }
        session.sendMessage(["refresh": true], replyHandler: nil) { [weak self] _ in
            Task { @MainActor in self?.error = "Could not reach iPhone. Open the phone app." }
        }
        #else
        guard !loading, let trip else { return }
        let revision = generation
        loading = true
        defer { loading = false }
        do {
            let value: Snapshot
            if demo { value = makeDemo(trip: trip) }
            else { value = try await request(Snapshot.self, url: url("arrivals", query: [.init(name: "route_id", value: trip.routeID), .init(name: "stop_id", value: trip.stopID)])) }
            guard generation == revision else { return }
            guard value.routeID == trip.routeID, value.stopID == trip.stopID, value.source == (demo ? "demo" : "live") else { throw URLError(.cannotParseResponse) }
            snapshot = value; error = nil; publishToWatch()
        } catch {
            guard generation == revision else { return }
            snapshot = nil; self.error = "Predictions unavailable. Check your connection and try again."; publishToWatch()
        }
        #endif
    }
    private func makeDemo(trip: SavedTrip) -> Snapshot {
        let now = Date()
        let needed = Double((trip.walkingMinutes + trip.bufferMinutes) * 60)
        let offsets: [Double]
        switch scenario {
        case .normal: offsets = [needed + 300, needed + 1020]
        case .close: offsets = [60, needed + 600]
        case .delayed: offsets = [needed + 900, needed + 1500]
        case .missing: offsets = []
        case .stale: offsets = [needed + 300, needed + 1020]
        case .final: offsets = [needed + 30]
        }
        let observed = scenario == .stale ? now.addingTimeInterval(-300) : now
        return Snapshot(routeID: trip.routeID, stopID: trip.stopID, source: "demo", updatedAt: observed,
                        arrivals: offsets.enumerated().map { Arrival(id: "demo-\($0.offset)", predictedAt: now.addingTimeInterval($0.element), observedAt: observed, finalScheduled: scenario == .final) },
                        alerts: scenario == .delayed ? ["Demo disruption: traffic delays on this route."] : [],
                        scheduleNote: "Simulated schedule and arrivals. Do not use demo data for travel.")
    }
}

extension TripStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            #if os(iOS)
            self.publishToWatch()
            #else
            self.receive(session.receivedApplicationContext)
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["state"] as? Data else { return }
        Task { @MainActor in self.receive(["state": data]) }
    }
    @MainActor private func receive(_ context: [String: Any]) {
        #if os(watchOS)
        guard let data = context["state"] as? Data, let state = try? Self.decoder.decode(Transfer.self, from: data) else { return }
        trip = state.trip; snapshot = state.snapshot; demo = state.demo; journeyPreview = state.journeyPreview; error = nil; persist()
        #endif
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        #if os(iOS)
        if message["refresh"] as? Bool == true { Task { @MainActor in await self.refresh() } }
        #endif
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

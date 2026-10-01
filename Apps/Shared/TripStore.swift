import Foundation
import SwiftUI
import WatchConnectivity

struct Transfer: Codable {
    var trip: SavedTrip?
    var snapshot: Snapshot?
    // Decode legacy mode only to reject saved/synced simulated trips.
    var demo: Bool? = nil
}

@MainActor
final class TripStore: NSObject, ObservableObject {
    @Published var trip: SavedTrip?
    @Published var snapshot: Snapshot?
    @Published var catalog: [Route] = []
    static let deployedEndpoint = "https://rutty-api.prouddune-2c1f0d5b.canadacentral.azurecontainerapps.io"
    @Published var endpoint = TripStore.deployedEndpoint
    @Published var error: String?
    @Published var loading = false
    @Published var syncNote: String?
    private var session: WCSession?
    private var generation = 0
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
    override init() {
        super.init()
        if UserDefaults.standard.bool(forKey: "live-only-migrated") {
            endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? Self.deployedEndpoint
        }
        if let data = UserDefaults.standard.data(forKey: "trip-state"), let state = try? Self.decoder.decode(Transfer.self, from: data) {
            apply(state)
        }
        UserDefaults.standard.removeObject(forKey: "journey-home")
        UserDefaults.standard.set(true, forKey: "live-only-migrated")
        persist()
        if WCSession.isSupported() {
            session = WCSession.default; session?.delegate = self; session?.activate()
        }
    }
    private var transfer: Transfer { Transfer(trip: trip, snapshot: snapshot) }
    private func apply(_ state: Transfer) {
        let saved = state.trip
        let simulated = state.demo == true || saved?.routeID.hasPrefix("demo-") == true || saved?.stopID.hasPrefix("demo-") == true
        trip = simulated ? nil : saved
        snapshot = !simulated && state.snapshot?.source == "live" ? state.snapshot : nil
    }
    private func persist() {
        if let data = try? Self.encoder.encode(transfer) { UserDefaults.standard.set(data, forKey: "trip-state") }
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
    }
    func publishToWatch() {
        persist()
        #if os(iOS)
        guard let session, session.activationState == .activated else { return }
        guard let data = try? Self.encoder.encode(transfer) else { return }
        do { try session.updateApplicationContext(["state": data]); syncNote = nil }
        catch { syncNote = "Watch sync pending. Open both apps to reconnect." }
        #endif
    }
    func configure(endpoint: String) async {
        generation += 1
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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
        var request = URLRequest(url: url); request.timeoutInterval = 60; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decoder.decode(type, from: data)
    }
    func loadCatalog() async {
        let revision = generation
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
            let value = try await request(Snapshot.self, url: url("arrivals", query: [.init(name: "route_id", value: trip.routeID), .init(name: "stop_id", value: trip.stopID)]))
            guard generation == revision else { return }
            guard value.routeID == trip.routeID, value.stopID == trip.stopID, value.source == "live" else { throw URLError(.cannotParseResponse) }
            snapshot = value; error = nil; publishToWatch()
        } catch {
            guard generation == revision else { return }
            snapshot = nil; self.error = "Predictions unavailable. Check your connection and try again."; publishToWatch()
        }
        #endif
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
        apply(state); error = nil; persist()
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

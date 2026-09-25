import SwiftUI

@main
@MainActor
struct RutgersDepartureApp: App {
    @StateObject private var store = TripStore()
    var body: some Scene { WindowGroup { HomeView().environmentObject(store).tint(.red) } }
}
@MainActor
struct HomeView: View {
    @EnvironmentObject var store: TripStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var setup = false
    @State private var connection = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    DepartureView()
                    if store.trip == nil { Button("Set up my trip") { setup = true }.buttonStyle(.borderedProminent) }
                    if store.demo {
                        Picker("Demo scenario", selection: $store.scenario) { ForEach(DemoScenario.allCases) { Text($0.rawValue).tag($0) } }
                        .onChange(of: store.scenario) { _, _ in Task { await store.refresh() } }
                    }
                    Button { Task { await store.refresh() } } label: { Label(store.loading ? "Refreshing…" : "Refresh arrivals", systemImage: "arrow.clockwise") }.disabled(store.loading || store.trip == nil)
                    Link("Check official TripShot", destination: URL(string: "https://rutgers.tripshot.com")!).font(.footnote)
                }.padding(24)
            }
            .navigationTitle("Time to go")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Data source", systemImage: "network") { connection = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Edit trip", systemImage: "slider.horizontal.3") { setup = true } }
            }
            .sheet(isPresented: $setup) { SetupView() }
            .sheet(isPresented: $connection) { ConnectionView() }
            .refreshable { await store.refresh() }
            .task {
                await store.loadCatalog()
                await store.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    if scenePhase == .active { await store.refresh() }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        }
    }
}
@MainActor
struct SetupView: View {
    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var routeID = ""
    @State private var stopID = ""
    @State private var walking = ""
    @State private var buffer = 2
    var route: Route? { store.catalog.first { $0.id == routeID } }
    var stop: Stop? { route?.stops.first { $0.id == stopID } }
    var valid: Bool { stop != nil && (1...120).contains(Int(walking) ?? 0) }
    var body: some View {
        NavigationStack {
            Form {
                if store.demo { Text("Demo routes and simulated arrivals. Select Live in Data source to use TripShot.").foregroundStyle(.orange) }
                Section("Your bus") {
                    Picker("Route", selection: $routeID) {
                        Text("Choose a route").tag("")
                        ForEach(store.catalog) { Text($0.name).tag($0.id) }
                    }.onChange(of: routeID) { _, _ in if route?.stops.contains(where: { $0.id == stopID }) != true { stopID = "" } }
                    Picker("Stop", selection: $stopID) {
                        Text("Choose a stop").tag("")
                        ForEach(route?.stops ?? []) { Text($0.name).tag($0.id) }
                    }.disabled(route == nil)
                }
                Section {
                    Text("On average, how many minutes does it take you to walk to this bus stop?").font(.headline)
                    TextField("Walking time in minutes", text: $walking).keyboardType(.numberPad)
                    Stepper("Safety buffer: \(buffer) min", value: $buffer, in: 0...30)
                } footer: { Text("Enter 1–120 minutes. Choose 0 for no extra buffer. We subtract both from the bus arrival estimate.") }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
                if store.catalog.isEmpty { Button("Retry loading routes") { Task { await store.loadCatalog() } } }
            }
            .navigationTitle("Your daily trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let route, let stop, let minutes = Int(walking) else { return }
                        let trip = SavedTrip(routeID: route.id, routeName: route.name, stopID: stop.id, stopName: stop.name, walkingMinutes: minutes, bufferMinutes: buffer)
                        Task { await store.save(trip) }
                        dismiss()
                    }.disabled(!valid)
                }
            }
            .task {
                if let trip = store.trip { routeID = trip.routeID; stopID = trip.stopID; walking = String(trip.walkingMinutes); buffer = trip.bufferMinutes }
                if store.catalog.isEmpty { await store.loadCatalog() }
            }
        }
    }
}
@MainActor
struct ConnectionView: View {
    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var demo = true
    @State private var endpoint = ""
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Use demo data", isOn: $demo)
                if !demo {
                    TextField("Backend URL", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("For Simulator: http://localhost:8000. On a phone, use your Mac’s local hostname or a deployed HTTPS endpoint.").font(.caption)
                }
                Text("Applying a data source clears your saved trip so route and stop IDs always match that source.").font(.caption)
            }.navigationTitle("Data source")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { Task { await store.configure(demo: demo, endpoint: endpoint) }; dismiss() } }
                }
                .onAppear { demo = store.demo; endpoint = store.endpoint }
        }
    }
}

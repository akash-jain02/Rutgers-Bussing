import SwiftUI
@main
@MainActor
struct RutgersDepartureWatchApp: App {
    @StateObject private var store = TripStore()
    var body: some Scene {
        WindowGroup {
            ScrollView {
                DepartureView(compact: true)
                Button("Refresh from iPhone", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.font(.caption)
            }.padding(.horizontal, 8).environmentObject(store).tint(.red)
        }
    }
}

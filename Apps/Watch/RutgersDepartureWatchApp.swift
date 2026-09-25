import SwiftUI
@main
@MainActor
struct RutgersDepartureWatchApp: App {
    @StateObject private var store = TripStore()
    var body: some Scene {
        WindowGroup {
            // A preview left behind (e.g. iPhone app closed on the detail screen) expires here instead of hiding live departures.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    if let journey = store.journeyPreview, journey.isActive(at: context.date) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DEMO · NOT LIVE").font(.caption2.bold()).foregroundStyle(.orange)
                            Text(journey.destination).font(.headline)
                            Text(journey.recommendation(at: context.date)).font(.system(.title3, design: .serif)).bold()
                            Text(journey.routes).font(.caption)
                            Text("Leave \(journey.leaveAt.formatted(date: .omitted, time: .shortened))").font(.caption)
                            Text("Preview only. Choose or change your journey on iPhone.").font(.caption2).foregroundStyle(.secondary)
                            Text("Generated \(journey.createdAt.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        DepartureView(compact: true)
                        Button("Refresh from iPhone", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.font(.caption)
                    }
                }.padding(.horizontal, 8).environmentObject(store).tint(.green)
            }
        }
    }
}

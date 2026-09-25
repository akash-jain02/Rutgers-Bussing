import SwiftUI
@main
@MainActor
struct RutgersDepartureWatchApp: App {
    @StateObject private var store = TripStore()
    var body: some Scene {
        WindowGroup {
            ScrollView {
                if let journey = store.journeyPreview {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DEMO · NOT LIVE").font(.caption2.bold()).foregroundStyle(.orange)
                        Text(journey.destination).font(.headline)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(journey.recommendation(at: context.date)).font(.system(.title3, design: .serif)).bold()
                        }
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

import SwiftUI

@MainActor
struct DepartureView: View {
    @EnvironmentObject var store: TripStore
    var compact = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let trip = store.trip {
                let recommendation = DepartureEngine.recommend(trip: trip, snapshot: store.snapshot, now: context.date)
                let arrivals = store.snapshot.map { DepartureEngine.visible($0, now: context.date) } ?? []
                VStack(alignment: .leading, spacing: compact ? 12 : 24) {
                    Label(store.demo ? "DEMO · NOT LIVE" : "TRIPSHOT ESTIMATES", systemImage: store.demo ? "testtube.2" : "antenna.radiowaves.left.and.right")
                        .font(.caption.bold()).foregroundStyle(store.demo ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trip.routeName).font(.headline).foregroundStyle(.red)
                        Text(trip.stopName).font(compact ? .headline : .title2).bold()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recommendation.title).font(compact ? .title3.bold() : .system(.largeTitle, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        if !compact { Text(recommendation.explanation).foregroundStyle(.secondary) }
                        if let departure = recommendation.departureAt {
                            Text("Leave by \(departure.formatted(date: .omitted, time: .shortened))").font(.subheadline.bold())
                        }
                    }
                    .padding(compact ? 12 : 22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 12) {
                        Text(compact ? "NEXT ARRIVAL" : "NEXT TWO ARRIVALS").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(Array(arrivals.prefix(compact ? 1 : 2))) { arrival in
                            HStack {
                                Image(systemName: "bus.fill").foregroundStyle(.red)
                                Text(arrival.predictedAt, style: .time)
                                Spacer()
                                Text("\(max(0, Int(ceil(arrival.predictedAt.timeIntervalSince(context.date) / 60)))) min").bold().monospacedDigit()
                            }
                        }
                        if arrivals.isEmpty { Text("No fresh predictions").foregroundStyle(.secondary) }
                        if !compact && arrivals.count == 1 { Text("Second arrival unavailable").font(.caption).foregroundStyle(.secondary) }
                    }
                    if compact { Text(recommendation.explanation).font(.caption).foregroundStyle(.secondary) }
                    Label("\(trip.walkingMinutes) min walk · \(trip.bufferMinutes) min buffer", systemImage: "figure.walk").font(.caption)
                    if let snapshot = store.snapshot {
                        ForEach(snapshot.alerts, id: \.self) { alert in Label(alert, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                        if let updated = snapshot.updatedAt {
                            Text("Data updated \(updated.formatted(date: .omitted, time: .standard))\(DepartureEngine.fresh(updated, now: context.date) ? "" : " · OUTDATED")").font(.caption2).foregroundStyle(.secondary)
                        } else { Text("Update time unavailable").font(.caption2) }
                        if !compact { Text(snapshot.scheduleNote).font(.caption2).foregroundStyle(.secondary) }
                    }
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    if let note = store.syncNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                ContentUnavailableView("Set up your trip", systemImage: "bus", description: Text(compact ? "Open the iPhone app to choose a route, stop and walking time." : "Choose your bus stop and tell us how long it takes you to walk there."))
            }
        }
    }
}

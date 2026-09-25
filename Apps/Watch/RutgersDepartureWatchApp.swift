import SwiftUI
@main
@MainActor
struct RutgersDepartureWatchApp: App {
    @StateObject private var store = TripStore()
    var body: some Scene {
        WindowGroup { WatchJourneyView().environmentObject(store) }
    }
}

private enum WatchPalette {
    static let accent = Color(hex: 0xA3C23A), muted = Color(hex: 0x8E8E93), surface = Color(hex: 0x1C1C1E)
    static func pace(_ pace: Pace) -> Color {
        switch pace { case .hurry: Color(hex: 0xFF6B5E); case .steady: accent; case .wait: Color(hex: 0x8FB4DD) }
    }
}

@MainActor
private struct WatchJourneyView: View {
    @EnvironmentObject var store: TripStore
    @State private var showLive = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        // Trips expire at arrival, so a trip left open on iPhone can't pin the watch.
                        if let journey = store.journey, journey.isActive(at: context.date) {
                            trip(journey, now: context.date)
                        } else if let home = store.home {
                            whereTo(home)
                        } else {
                            setHome
                        }
                    }.padding(.horizontal, 4)
                }
            }
            .navigationDestination(isPresented: $showLive) {
                ScrollView {
                    DepartureView(compact: true)
                    Button("Refresh from iPhone", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.font(.caption)
                }.padding(.horizontal, 8).tint(.red)
            }
        }
    }
    private func headline(_ lead: String, _ accent: String, size: CGFloat) -> some View {
        Text("\(lead)\(Text(accent).italic().foregroundStyle(WatchPalette.accent))").font(.system(size: size, weight: .light, design: .serif))
    }
    private func whereTo(_ home: HomePreference) -> some View {
        Group {
            Text(home.stop.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(WatchPalette.muted).lineLimit(1)
            headline("Where ", "to?", size: 26)
            ForEach(CampusChoice.all.filter { $0.id != home.campusID }) { place in
                Button {
                    store.journey = JourneyPreview.options(home: home, destination: place).first { $0.pace == .steady }
                    store.publishToWatch()
                } label: {
                    HStack(spacing: 8) {
                        Text(place.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(JourneyPreview.legs(from: home.campusID, to: place.id).map { $0.routes[0] }.joined(separator: "→"))
                            .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(WatchPalette.muted)
                    }.padding(.horizontal, 12).frame(minHeight: 38).background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Text("DEMO TIMES · NOT LIVE").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
            Button("Live arrivals") { showLive = true }.font(.caption).foregroundStyle(WatchPalette.accent)
        }
    }
    private func trip(_ journey: JourneyPreview, now: Date) -> some View {
        let remaining = journey.secondsToLeave(at: now)
        let next = journey.nextStep(at: now)
        return Group {
            Text(journey.destination.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(WatchPalette.muted).lineLimit(1)
            Text("\(Text(journey.pace.label.uppercased()).foregroundStyle(WatchPalette.pace(journey.pace))) · \(Text("DEMO").foregroundStyle(.orange))")
                .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(WatchPalette.muted)
            Text(remaining == nil ? "Time to go" : "Leave in").font(.system(size: 12)).foregroundStyle(WatchPalette.muted).padding(.bottom, -6)
            Text(remaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "Go now")
                .font(.system(size: 44, weight: .light, design: .serif)).monospacedDigit()
            HStack(spacing: 8) {
                if let route = next.route {
                    Text(route).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(.white, in: RoundedRectangle(cornerRadius: 5))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(next.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(next.at.clock) · \(next.detail)").font(.system(size: 10, design: .monospaced)).foregroundStyle(WatchPalette.muted).lineLimit(1)
                }
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            Button("End trip") { store.journey = nil; store.publishToWatch() }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(WatchPalette.accent).frame(maxWidth: .infinity, minHeight: 32)
        }
    }
    private var setHome: some View {
        VStack(spacing: 6) {
            headline("Set ", "home", size: 22)
            Text("Finish on iPhone").font(.system(size: 12)).foregroundStyle(WatchPalette.muted)
        }.frame(maxWidth: .infinity, minHeight: 150)
    }
}

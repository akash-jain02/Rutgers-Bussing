import SwiftUI

private enum JourneyStyle {
    static let olive = Color(red: 0.32, green: 0.38, blue: 0.055)
    static let background = Color(uiColor: .systemGroupedBackground)
}
private struct JourneyCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08)))
    }
}
private struct DemoNotice: View {
    var body: some View {
        Label("DEMO JOURNEYS · NOT LIVE", systemImage: "testtube.2")
            .font(.caption.bold()).foregroundStyle(.orange)
            .accessibilityLabel("Demo journeys. Not live. Do not use for travel.")
    }
}
@MainActor
struct JourneyHomeScreen: View {
    @EnvironmentObject var store: TripStore
    @AppStorage("journey-home") private var savedHome = Data()
    @State private var editingHome = false
    @State private var liveScreen = false
    private var home: HomePreference? { try? JSONDecoder().decode(HomePreference.self, from: savedHome) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DemoNotice()
                    if let home {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("FROM · \(home.walk) MIN WALK").font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(home.stop).font(.headline)
                                Text("\(home.buffer) min safety buffer").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") { editingHome = true }.frame(minHeight: 44)
                        }.modifier(JourneyCard())
                        Text("Where to?").font(.system(.largeTitle, design: .serif)).bold()
                        ForEach(CampusChoice.all.filter { $0.id != home.campusID }) { campus in
                            NavigationLink { DestinationScreen(home: home, campus: campus) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(campus.name).font(.title3.weight(.medium))
                                        Text("Choose your arrival stop").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right")
                                }.modifier(JourneyCard())
                            }.buttonStyle(.plain)
                        }
                    } else {
                        Text("A little less waiting.").font(.system(.largeTitle, design: .serif)).bold()
                        Text("Save your usual stop and tell us how long you take to walk there.").foregroundStyle(.secondary)
                        Button("Set up home", systemImage: "house") { editingHome = true }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Text("Preview the new journey screens with simulated routes and times. For existing TripShot arrival estimates, open Live arrivals.").font(.footnote).foregroundStyle(.secondary)
                    Button("Live arrivals", systemImage: "antenna.radiowaves.left.and.right") { liveScreen = true }
                }.padding(20)
            }.background(JourneyStyle.background).navigationTitle("Rutgers")
                .sheet(isPresented: $editingHome) {
                    HomeSetupScreen(existing: home) { value in
                        if let data = try? JSONEncoder().encode(value) { savedHome = data }
                        store.journeyPreview = nil; store.publishToWatch()
                    }
                }
                .sheet(isPresented: $liveScreen) { HomeView() }
        }.tint(JourneyStyle.olive)
    }
}
@MainActor
private struct HomeSetupScreen: View {
    var existing: HomePreference?
    var save: (HomePreference) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var campus: CampusChoice?
    @State private var stop = ""
    @State private var walk = ""
    @State private var buffer = 2
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoNotice()
                    Text(campus == nil ? "STEP 1 OF 2" : "STEP 2 OF 2").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(campus == nil ? "Where do you live?" : "Your nearest stop").font(.system(.largeTitle, design: .serif))
                    if let campus {
                        Button("Change campus") { self.campus = nil; stop = "" }
                        Text(campus.name).font(.headline)
                        ForEach(campus.stops, id: \.self) { name in
                            Button { stop = name } label: {
                                HStack { Text(name); Spacer(); Image(systemName: stop == name ? "checkmark.circle.fill" : "circle") }.modifier(JourneyCard())
                            }.buttonStyle(.plain).accessibilityAddTraits(stop == name ? .isSelected : [])
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("On average, how many minutes does it take you to walk to this stop?").font(.headline)
                            TextField("Walking time in minutes", text: $walk).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            Text("Enter 1–120 minutes at your usual pace.").font(.caption).foregroundStyle(.secondary)
                            Stepper("Safety buffer: \(buffer) min", value: $buffer, in: 0...30)
                        }.modifier(JourneyCard())
                        Button("Save home") {
                            guard let minutes = Int(walk) else { return }
                            save(HomePreference(campusID: campus.id, stop: stop, walk: minutes, buffer: buffer)); dismiss()
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(stop.isEmpty || !(1...120).contains(Int(walk) ?? 0))
                    } else {
                        ForEach(CampusChoice.all) { choice in
                            Button { campus = choice; stop = "" } label: {
                                HStack { Text(choice.name).font(.headline); Spacer(); Image(systemName: "chevron.right") }.modifier(JourneyCard())
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(20)
            }.background(JourneyStyle.background)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear {
                    if let existing { campus = CampusChoice.all.first { $0.id == existing.campusID }; stop = existing.stop; walk = String(existing.walk); buffer = existing.buffer }
                }
        }.tint(JourneyStyle.olive)
    }
}
@MainActor
private struct DestinationScreen: View {
    let home: HomePreference
    let campus: CampusChoice
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DemoNotice()
                Text("Where on \(campus.name)?").font(.system(.largeTitle, design: .serif))
                ForEach(campus.stops, id: \.self) { stop in
                    NavigationLink { JourneyOptionsScreen(home: home, campus: campus, stop: stop) } label: {
                        HStack { Text(stop).font(.headline); Spacer(); Image(systemName: "chevron.right") }.modifier(JourneyCard())
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(JourneyStyle.background).navigationTitle("Destination").navigationBarTitleDisplayMode(.inline)
    }
}
@MainActor
private struct JourneyOptionsScreen: View {
    let home: HomePreference
    let campus: CampusChoice
    let stop: String
    @State private var options: [JourneyPreview] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DemoNotice()
                Text("Pick your departure").font(.system(.largeTitle, design: .serif))
                Text("\(home.stop) → \(stop)").font(.subheadline).foregroundStyle(.secondary)
                ForEach(options) { option in
                    NavigationLink { JourneyDetailScreen(journey: option) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(option.title.uppercased()).font(.caption.monospaced().bold())
                                Spacer()
                                if option.recommended { Text("SUGGESTED").font(.caption2.bold()).foregroundStyle(JourneyStyle.olive) }
                            }
                            Text("Leave \(option.leaveAt.formatted(date: .omitted, time: .shortened))").font(.system(.title2, design: .serif))
                            Text("\(option.routes) · Arrive \(option.arriveAt.formatted(date: .omitted, time: .shortened))").font(.subheadline)
                            Text("\(home.walk) min walk + \(home.buffer) min buffer").font(.caption).foregroundStyle(.secondary)
                        }.modifier(JourneyCard())
                    }.buttonStyle(.plain)
                }
                Button("Refresh demo options", systemImage: "arrow.clockwise") { refresh() }
                Text("All three options use your usual walking time and full buffer. Route combinations and connection times are illustrative.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.background(JourneyStyle.background).navigationTitle("Options").navigationBarTitleDisplayMode(.inline)
            .onAppear { refresh() }
    }
    private func refresh() { options = JourneyPreview.options(home: home, destination: campus, stop: stop) }
}
@MainActor
private struct JourneyDetailScreen: View {
    let journey: JourneyPreview
    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoNotice()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(journey.title.uppercased()).font(.caption.monospaced()).foregroundStyle(JourneyStyle.olive)
                        Text(journey.recommendation(at: context.date)).font(.system(.largeTitle, design: .serif)).bold()
                        Text("Leave \(journey.leaveAt.formatted(date: .omitted, time: .shortened)) · arrive \(journey.arriveAt.formatted(date: .omitted, time: .shortened))").font(.subheadline)
                    }.modifier(JourneyCard())
                }
                ForEach(journey.steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: step.route == nil ? "circle.inset.filled" : "bus.fill").foregroundStyle(JourneyStyle.olive).frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.title).font(.headline)
                            Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            Text(step.at, style: .time).font(.subheadline.monospaced())
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Demo generated \(journey.createdAt.formatted(date: .omitted, time: .standard)). Refresh after 90 seconds. Do not use these times for travel.").font(.caption).foregroundStyle(.secondary)
                Button("Choose another departure") { dismiss() }.buttonStyle(.bordered)
            }.padding(20)
        }.background(JourneyStyle.background).navigationTitle("Your trip").navigationBarTitleDisplayMode(.inline)
            .onAppear { store.journeyPreview = journey; store.publishToWatch() }
            .onDisappear { if store.journeyPreview?.id == journey.id { store.journeyPreview = nil; store.publishToWatch() } }
    }
}

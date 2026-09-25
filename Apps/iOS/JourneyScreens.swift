import SwiftUI

// Tokens from the Bus Concept design (light only). ponytail: system serif/mono stand in for Fraunces/DM Mono; bundle the fonts if the match matters.
private enum Palette {
    static let bg = Color(hex: 0xF7F8FA), card = Color.white, interactive = Color(hex: 0xEEF1F4)
    static let border = Color(hex: 0x111827).opacity(0.12), strongBorder = Color(hex: 0x111827).opacity(0.2)
    static let text = Color(hex: 0x14181F), muted = Color(hex: 0x4F5865)
    static let accent = Color(hex: 0x51620E), warn = Color(hex: 0x8A5A00)
    static func pace(_ pace: Pace) -> Color {
        switch pace { case .hurry: Color(hex: 0xB42318); case .steady: accent; case .wait: Color(hex: 0x38536F) }
    }
}
private func title(_ lead: String, _ accent: String, _ tail: String, size: CGFloat = 32) -> some View {
    Text("\(lead)\(Text(accent).italic().foregroundStyle(Palette.accent))\(tail)")
        .font(.system(size: size, weight: .light, design: .serif)).tracking(-0.02 * size).foregroundStyle(Palette.text)
}
private func eyebrow(_ text: String, color: Color = Palette.muted) -> some View {
    Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(color)
}
private func routeChip(_ code: String) -> some View {
    Text(code).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.text, in: RoundedRectangle(cornerRadius: 5))
}
private func backButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button("‹ \(label)", action: action).font(.system(size: 15)).foregroundStyle(Palette.accent).frame(minHeight: 44)
}
private struct Card: ViewModifier {
    var border = Palette.border
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border))
            .shadow(color: Palette.text.opacity(0.06), radius: 1.5, y: 1)
    }
}
private struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
private struct DemoFooter: View {
    var body: some View {
        Text("DEMO TIMES · NOT LIVE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
            .foregroundStyle(Palette.warn).frame(maxWidth: .infinity).accessibilityLabel("Demo times. Not live. Do not use for travel.")
    }
}

@MainActor
struct JourneyHomeScreen: View {
    enum Screen { case campus, stop, home, options, trip }
    @EnvironmentObject var store: TripStore
    @State private var screen = Screen.home
    @State private var campus: CampusChoice?
    @State private var stop: String?
    @State private var walk = 5
    @State private var destination: CampusChoice?
    @State private var options: [JourneyPreview] = []
    @State private var liveScreen = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch screen {
                case .campus: campusScreen
                case .stop: stopScreen
                case .home: homeScreen
                case .options: optionsScreen
                case .trip: tripScreen
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 48)
        }
        .background(Palette.bg).foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.light)
        .onAppear { if store.home == nil { screen = .campus } }
        .sheet(isPresented: $liveScreen) { HomeView() }
    }

    // MARK: Setup
    private var campusScreen: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) { eyebrow("STEP 1 OF 2"); title("Where do you ", "live", "?") }.padding(.top, 12)
            ForEach(CampusChoice.all) { choice in
                Button {
                    if campus?.id != choice.id { stop = store.home?.campusID == choice.id ? store.home?.stop : nil }
                    campus = choice; walk = store.home?.walk ?? walk; screen = .stop
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.name).font(.system(size: 17, weight: .medium))
                            Text(choice.stops.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 20)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal, 18).frame(minHeight: 64).modifier(Card())
                }.buttonStyle(Press())
            }
        }
    }
    private var stopScreen: some View {
        Group {
            backButton("Campus") { screen = .campus }
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("STEP 2 OF 2 · \((campus?.name ?? "").uppercased())")
                title("Your nearest ", "stop", "")
            }
            VStack(spacing: 0) {
                ForEach(campus?.stops ?? [], id: \.self) { name in
                    let isOn = name == stop
                    Button { stop = name } label: {
                        HStack {
                            Text(name).font(.system(size: 16, weight: isOn ? .semibold : .regular))
                            Spacer()
                            Circle().strokeBorder(isOn ? Palette.accent : Palette.strongBorder, lineWidth: 2).frame(width: 22, height: 22)
                                .overlay(Circle().fill(isOn ? Palette.accent : .clear).frame(width: 10, height: 10))
                        }.padding(.horizontal, 18).frame(minHeight: 56).background(isOn ? Palette.accent.opacity(0.06) : Palette.card)
                    }.buttonStyle(.plain).accessibilityAddTraits(isOn ? .isSelected : [])
                    Divider()
                }
            }.clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border))
            HStack(spacing: 12) {
                Text("Walk to the stop").font(.system(size: 15, weight: .medium))
                Spacer()
                stepperButton("−", label: "Shorter walk") { walk = max(1, walk - 1) }
                Text("\(walk) min").font(.system(size: 16, weight: .medium, design: .monospaced)).frame(minWidth: 52)
                stepperButton("+", label: "Longer walk") { walk = min(30, walk + 1) }
            }.padding(.horizontal, 18).padding(.vertical, 14).modifier(Card())
            Button {
                guard let campus, let stop else { return }
                store.home = HomePreference(campusID: campus.id, stop: stop, walk: walk, buffer: store.home?.buffer ?? 2)
                store.publishToWatch(); screen = .home
            } label: {
                Text("Save home").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 12)).shadow(color: Palette.accent.opacity(0.32), radius: 8, y: 6)
            }.buttonStyle(Press()).disabled(stop == nil).opacity(stop == nil ? 0.5 : 1).padding(.top, 12)
        }
    }
    private func stepperButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol).font(.system(size: 20)).frame(width: 44, height: 44)
                .background(Palette.interactive, in: Circle()).overlay(Circle().stroke(Palette.strongBorder))
        }.buttonStyle(Press()).accessibilityLabel(label)
    }

    // MARK: Where to
    @ViewBuilder private var homeScreen: some View {
        if let home = store.home {
            HStack(spacing: 12) {
                Circle().fill(Palette.accent).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FROM · \(home.walk) MIN WALK").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.1).foregroundStyle(Palette.muted)
                    Text("\(home.stop) · \(CampusChoice.named(home.campusID)?.name ?? "")").font(.system(size: 14, weight: .medium)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Change") { campus = CampusChoice.named(home.campusID); stop = home.stop; walk = home.walk; screen = .campus }
                    .font(.system(size: 14)).frame(minHeight: 44)
            }.padding(.horizontal, 14).padding(.vertical, 4).modifier(Card()).padding(.top, 8)
            title("Where ", "to", "?", size: 40).padding(.top, 8)
            ForEach(CampusChoice.all.filter { $0.id != home.campusID }) { place in
                let legs = JourneyPreview.legs(from: home.campusID, to: place.id)
                Button {
                    destination = place; options = JourneyPreview.options(home: home, destination: place); screen = .options
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.name).font(.system(size: 18, weight: .medium))
                            HStack(spacing: 6) {
                                ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                                    if index > 0 { Text("→").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                                    routeChip(leg.routes.joined(separator: "/"))
                                }
                                Text(legs.count > 1 ? "1 TRANSFER" : "DIRECT").font(.system(size: 11, design: .monospaced)).tracking(0.4)
                                    .foregroundStyle(legs.count > 1 ? Palette.warn : Palette.muted).padding(.leading, 2)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 20)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal, 18).frame(minHeight: 76).modifier(Card())
                }.buttonStyle(Press())
            }
            DemoFooter().padding(.top, 4)
            Button("Live arrivals", systemImage: "antenna.radiowaves.left.and.right") { liveScreen = true }
                .font(.system(size: 14)).frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: Pick your pace
    private var tripTitle: String {
        "\(CampusChoice.named(store.home?.campusID ?? "")?.name ?? "") → \(destination?.name ?? "")".uppercased()
    }
    private var optionsScreen: some View {
        Group {
            backButton("Where to") { screen = .home }
            VStack(alignment: .leading, spacing: 8) { eyebrow(tripTitle); title("Pick your ", "pace", "") }
            ForEach(options) { option in
                Button { store.journey = option; store.publishToWatch(); screen = .trip } label: { optionCard(option) }.buttonStyle(Press())
            }
            DemoFooter()
        }
    }
    private func optionCard(_ option: JourneyPreview) -> some View {
        let color = Palette.pace(option.pace)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                eyebrow(option.pace.label.uppercased(), color: color)
                if option.recommended {
                    Text("BEST").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.accent.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Palette.accent.opacity(0.28)))
                }
                Spacer()
                Text("\(option.totalMinutes) min total").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(option.leaveInMinutes <= 0 ? "Leave now" : "Leave in \(option.leaveInMinutes) min").font(.system(size: 26, design: .serif))
                Spacer()
                Text(option.note).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 6) {
                ForEach(Array(option.boardings.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Text("→") }
                    routeChip(step.route ?? "")
                    Text(step.at.clock)
                }
                Spacer(minLength: 0)
                Text("arrive \(option.arriveAt.clock)")
            }.font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .overlay(alignment: .leading) { color.frame(width: 4) }
        .modifier(Card(border: option.recommended ? Palette.accent.opacity(0.35) : Palette.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Trip
    @ViewBuilder private var tripScreen: some View {
        if let journey = store.journey {
            let color = Palette.pace(journey.pace)
            backButton("Options") { endTrip(); screen = .options }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = journey.secondsToLeave(at: context.date)
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("\(journey.pace.label.uppercased()) · \(tripTitle)", color: color)
                    Text(remaining == nil ? "Time to go" : "Leave in").font(.system(size: 14)).foregroundStyle(Palette.muted).padding(.top, 6)
                    Text(remaining.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "Go now")
                        .font(.system(size: 64, weight: .light, design: .serif)).monospacedDigit().contentTransition(.numericText())
                    Text("Leave \(journey.leaveAt.clock) · arrive \(journey.arriveAt.clock)").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.muted).padding(.top, 6)
                }.padding(20).overlay(alignment: .top) { color.frame(height: 3) }.modifier(Card()).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            VStack(spacing: 0) {
                ForEach(journey.steps) { step in timelineRow(step, isLast: step.id == journey.steps.count - 1) }
            }
            DemoFooter()
            Button { endTrip(); screen = .home } label: {
                Text("New trip").font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.strongBorder))
            }.buttonStyle(Press())
        }
    }
    private func timelineRow(_ step: PreviewStep, isLast: Bool) -> some View {
        // Walk, transfer and arrival share a ring marker; only boardings get a route chip.
        let ring = step.id == 0 ? Palette.muted : isLast ? Palette.accent : Palette.warn
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                if let route = step.route { routeChip(route).padding(.top, 2) } else {
                    Circle().strokeBorder(ring, lineWidth: 2).background(Circle().fill(Palette.bg)).frame(width: 12, height: 12).padding(.top, 5)
                }
                Rectangle().fill(isLast ? .clear : Palette.text.opacity(0.15)).frame(width: 2).frame(minHeight: 18)
            }.frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title).font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text(step.at.clock).font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                Text(step.detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.padding(.bottom, 18)
        }
    }
    private func endTrip() { store.journey = nil; store.publishToWatch() }
}

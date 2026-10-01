import SwiftUI

@MainActor
struct JourneyHomeScreen: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Departures", systemImage: "bus.fill") }
            ContentUnavailableView("Journey planning unavailable", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Destination and transfer planning are not connected to verified live data yet. Use Departures to choose a route and stop and see when to leave."))
                .tabItem { Label("Journeys", systemImage: "map") }
        }.tint(Color(red: 0.32, green: 0.38, blue: 0.055))
    }
}

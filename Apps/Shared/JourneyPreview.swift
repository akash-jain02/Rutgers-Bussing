import Foundation

struct CampusChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let stops: [String]
    static let all = [
        CampusChoice(id: "livi", name: "Livingston", stops: ["Livingston Student Center", "Livingston Plaza", "Quads"]),
        CampusChoice(id: "busch", name: "Busch", stops: ["Busch Student Center", "Hill Center", "Allison Road Classrooms"]),
        CampusChoice(id: "dt", name: "Downtown New Brunswick", stops: ["SoCam Apartments", "New Brunswick Train Station"]),
        CampusChoice(id: "cd", name: "Cook / Douglass", stops: ["Douglass Student Center", "Biel Road", "Lipman Hall"]),
        CampusChoice(id: "ca", name: "College Avenue", stops: ["College Avenue Student Center", "Student Activities Center", "The Yard"])
    ]
}
struct HomePreference: Codable {
    var campusID: String
    var stop: String
    var walk: Int
    var buffer: Int
}
struct PreviewStep: Codable, Identifiable {
    var id: Int
    var title: String
    var detail: String
    var at: Date
    var route: String?
}
struct JourneyPreview: Codable, Identifiable {
    var id: String
    var title: String
    var origin: String
    var destination: String
    var createdAt: Date
    var leaveAt: Date
    var arriveAt: Date
    var steps: [PreviewStep]
    var buffer: Int
    var recommended: Bool
    var routes: String { steps.compactMap(\.route).joined(separator: " → ") }
    func recommendation(at now: Date) -> String {
        if now.timeIntervalSince(createdAt) > 90 || now < createdAt.addingTimeInterval(-30) { return "Refresh options" }
        if now > leaveAt { return "Choose another departure" }
        let seconds = leaveAt.timeIntervalSince(now)
        if seconds < 60 { return "Go now" }
        let minutes = Int(seconds / 60)
        return "Wait \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
    static func options(home: HomePreference, destination: CampusChoice, stop: String, now: Date = Date()) -> [JourneyPreview] {
        // Visual fixtures only. These route pairs are not a verified live journey planner.
        let pair = home.campusID + ">" + destination.id
        let routes: [String]
        switch pair {
        case "dt>livi": routes = ["EE", "LX"]
        case "livi>dt": routes = ["LX", "EE"]
        case "ca>livi", "livi>ca": routes = ["LX"]
        case "ca>busch", "busch>ca": routes = ["H"]
        case "busch>livi", "livi>busch": routes = ["B"]
        case "busch>cd", "cd>busch": routes = ["REXB"]
        case "livi>cd", "cd>livi": routes = ["REXL"]
        case "dt>busch": routes = ["EE", "H"]
        case "busch>dt": routes = ["H", "EE"]
        default: routes = ["EE"]
        }
        return ["Earliest", "Recommended", "Later"].enumerated().map { index, title in
            let leave = now.addingTimeInterval(Double([30, 300, 900][index]))
            var time = leave
            var steps = [PreviewStep(id: 0, title: "Walk to \(home.stop)", detail: "\(home.walk) min at your usual pace", at: time)]
            time = time.addingTimeInterval(Double((home.walk + home.buffer) * 60))
            for (leg, route) in routes.enumerated() {
                if leg > 0 {
                    let transfer = routes == ["EE", "LX"] ? "Student Activities Center" : "College Avenue Student Center"
                    steps.append(PreviewStep(id: steps.count, title: "Transfer at \(transfer)", detail: "Demo: 5 min connection allowance; location needs live verification", at: time))
                    time = time.addingTimeInterval(300)
                }
                steps.append(PreviewStep(id: steps.count, title: "Board \(route)", detail: "Demo ride · 12 min", at: time, route: route))
                time = time.addingTimeInterval(720)
            }
            steps.append(PreviewStep(id: steps.count, title: "Arrive at \(stop)", detail: destination.name, at: time))
            return JourneyPreview(id: UUID().uuidString, title: title, origin: home.stop, destination: stop, createdAt: now, leaveAt: leave, arriveAt: time, steps: steps, buffer: home.buffer, recommended: index == 1)
        }
    }
}

import Foundation

struct CampusChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let stops: [String]
    /// Arrival stop for trips to this campus.
    var hub: String { stops[0] }
    static let all = [
        CampusChoice(id: "livi", name: "Livingston", stops: ["Livingston Student Center", "Livingston Plaza", "Quads"]),
        CampusChoice(id: "busch", name: "Busch", stops: ["Busch Student Center", "Hill Center", "Allison Road Classrooms"]),
        CampusChoice(id: "dt", name: "Downtown NB", stops: ["Rockoff Hall", "SoCam Apts", "NB Train Station"]),
        CampusChoice(id: "cd", name: "Cook / Douglass", stops: ["Douglass Student Center", "Biel Road", "Lipman Hall"]),
        CampusChoice(id: "ca", name: "College Ave", stops: ["College Ave Student Center", "Scott Hall", "Student Activities Center"])
    ]
    static func named(_ id: String) -> CampusChoice? { all.first { $0.id == id } }
}
struct HomePreference: Codable, Equatable {
    var campusID: String
    var stop: String
    var walk: Int
    var buffer: Int
}
/// One ride; `routes` are interchangeable alternatives, rotated across the three paces.
struct RouteLeg {
    let routes: [String]
    let ride: Int
}
enum Pace: String, Codable, CaseIterable {
    case hurry, steady, wait
    var label: String { rawValue.capitalized }
    func note(buffer: Int) -> String {
        switch self {
        case .hurry: "Brisk walk, no buffer"
        case .steady: buffer > 0 ? "\(buffer) min to spare" : "Normal walk"
        case .wait: "Relax first"
        }
    }
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
    var pace: Pace
    var note: String
    var origin: String
    var destination: String
    var createdAt: Date
    var leaveAt: Date
    var arriveAt: Date
    var steps: [PreviewStep]
    var recommended: Bool { pace == .steady }
    var boardings: [PreviewStep] { steps.filter { $0.route != nil } }
    var totalMinutes: Int { Int(arriveAt.timeIntervalSince(leaveAt) / 60) }
    var leaveInMinutes: Int { Int(leaveAt.timeIntervalSince(createdAt) / 60) }
    /// A trip stays on screen until its arrival time, so a left-behind trip never pins the watch.
    func isActive(at now: Date) -> Bool { now <= arriveAt }
    /// Seconds until leave-by, or nil once it's time to go.
    func secondsToLeave(at now: Date) -> Int? {
        let seconds = Int(leaveAt.timeIntervalSince(now).rounded())
        return seconds > 0 ? seconds : nil
    }
    func nextStep(at now: Date) -> PreviewStep { steps.first { $0.at > now.addingTimeInterval(-30) } ?? steps[steps.count - 1] }

    // Demo fixtures from the Bus Concept design. Not a verified live journey planner.
    static let transferStop = "College Ave Student Center"
    static let headway = ["A": 8, "H": 8, "LX": 6, "EE": 10, "F": 12, "B": 7, "REXB": 15, "REXL": 15]
    static let plans: [String: [RouteLeg]] = [
        "ca>busch": [RouteLeg(routes: ["A", "H"], ride: 12)], "ca>livi": [RouteLeg(routes: ["LX"], ride: 10)],
        "ca>cd": [RouteLeg(routes: ["EE", "F"], ride: 14)], "ca>dt": [RouteLeg(routes: ["EE"], ride: 6)],
        "busch>livi": [RouteLeg(routes: ["B"], ride: 9)], "busch>cd": [RouteLeg(routes: ["REXB"], ride: 20)],
        "busch>dt": [RouteLeg(routes: ["H", "A"], ride: 12), RouteLeg(routes: ["EE"], ride: 6)],
        "livi>cd": [RouteLeg(routes: ["REXL"], ride: 22)],
        "livi>dt": [RouteLeg(routes: ["LX"], ride: 10), RouteLeg(routes: ["EE"], ride: 6)],
        "cd>dt": [RouteLeg(routes: ["EE"], ride: 10)]
    ]
    static func legs(from origin: String, to destination: String) -> [RouteLeg] {
        plans["\(origin)>\(destination)"] ?? plans["\(destination)>\(origin)"]?.reversed() ?? []
    }
    static func options(home: HomePreference, destination: CampusChoice, now: Date = Date()) -> [JourneyPreview] {
        let legs = legs(from: home.campusID, to: destination.id)
        guard let first = legs.first else { return [] }
        let gap = max(4, Int((Double(headway[first.routes[0]] ?? 8) / Double(first.routes.count)).rounded()))
        let minute = { (offset: Int) in now.addingTimeInterval(Double(offset * 60)) }
        return Pace.allCases.enumerated().map { index, pace in
            let board = home.walk + 1 + index * gap
            let leave = index == 0 ? 0 : max(0, board - home.walk - home.buffer)
            var time = board
            var steps = [PreviewStep(id: 0, title: "Walk to \(home.stop)", detail: "\(home.walk) min walk", at: minute(leave))]
            for (leg, ride) in legs.enumerated() {
                let code = ride.routes[index % ride.routes.count]
                if leg > 0 {
                    let wait = 2 + (time + index) % max(3, (headway[code] ?? 8) - 2)
                    steps.append(PreviewStep(id: steps.count, title: "Get off at \(transferStop)", detail: "Wait \(wait) min for the \(code)", at: minute(time)))
                    time += wait
                }
                steps.append(PreviewStep(id: steps.count, title: "Board the \(code)", detail: "\(ride.ride) min ride", at: minute(time), route: code))
                time += ride.ride
            }
            steps.append(PreviewStep(id: steps.count, title: "Arrive at \(destination.hub)", detail: destination.name, at: minute(time)))
            return JourneyPreview(id: UUID().uuidString, pace: pace, note: pace.note(buffer: home.buffer), origin: home.stop, destination: destination.name,
                                  createdAt: now, leaveAt: minute(leave), arriveAt: minute(time), steps: steps)
        }
    }
}
extension Date {
    /// "4:57" — the design drops AM/PM.
    var clock: String {
        let time = Calendar.current.dateComponents([.hour, .minute], from: self)
        let hour = (time.hour ?? 0) % 12
        return "\(hour == 0 ? 12 : hour):" + String(format: "%02d", time.minute ?? 0)
    }
}

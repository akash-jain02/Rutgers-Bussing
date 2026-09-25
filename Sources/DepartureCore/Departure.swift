import Foundation

public struct Stop: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct Route: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var stops: [Stop]
    public init(id: String, name: String, stops: [Stop]) { self.id = id; self.name = name; self.stops = stops }
}
public struct SavedTrip: Codable, Equatable, Sendable {
    public var routeID: String
    public var routeName: String
    public var stopID: String
    public var stopName: String
    public var walkingMinutes: Int
    public var bufferMinutes: Int
    public init(routeID: String, routeName: String, stopID: String, stopName: String, walkingMinutes: Int, bufferMinutes: Int) {
        self.routeID = routeID; self.routeName = routeName; self.stopID = stopID; self.stopName = stopName
        self.walkingMinutes = walkingMinutes; self.bufferMinutes = bufferMinutes
    }
}
public struct Arrival: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var predictedAt: Date
    public var observedAt: Date
    public var finalScheduled: Bool
    public init(id: String, predictedAt: Date, observedAt: Date, finalScheduled: Bool = false) {
        self.id = id; self.predictedAt = predictedAt; self.observedAt = observedAt; self.finalScheduled = finalScheduled
    }
}
public struct Snapshot: Codable, Sendable {
    public var routeID: String
    public var stopID: String
    public var source: String
    public var updatedAt: Date?
    public var arrivals: [Arrival]
    public var alerts: [String]
    public var scheduleNote: String
    public init(routeID: String, stopID: String, source: String, updatedAt: Date?, arrivals: [Arrival], alerts: [String] = [], scheduleNote: String = "Final service is not verified.") {
        self.routeID = routeID; self.stopID = stopID; self.source = source; self.updatedAt = updatedAt
        self.arrivals = arrivals; self.alerts = alerts; self.scheduleNote = scheduleNote
    }
}
public struct Recommendation: Equatable, Sendable {
    public var title: String
    public var explanation: String
    public var departureAt: Date?
    public var arrivalID: String?
}
public enum DepartureEngine {
    public static let maximumAge: TimeInterval = 90
    public static func fresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return (-30...maximumAge).contains(now.timeIntervalSince(date))
    }
    public static func visible(_ snapshot: Snapshot, now: Date) -> [Arrival] {
        guard fresh(snapshot.updatedAt, now: now) else { return [] }
        return snapshot.arrivals.filter { $0.predictedAt >= now && fresh($0.observedAt, now: now) }.sorted { $0.predictedAt < $1.predictedAt }
    }
    public static func recommend(trip: SavedTrip, snapshot: Snapshot?, now: Date) -> Recommendation {
        func unavailable(_ text: String) -> Recommendation { .init(title: "Check arrivals", explanation: text, departureAt: nil, arrivalID: nil) }
        guard (1...120).contains(trip.walkingMinutes), (0...30).contains(trip.bufferMinutes) else { return unavailable("Set your walking time and buffer.") }
        guard let snapshot, snapshot.routeID == trip.routeID, snapshot.stopID == trip.stopID else { return unavailable("Arrival predictions are unavailable for this trip.") }
        guard fresh(snapshot.updatedAt, now: now) else { return unavailable("Arrival data is outdated or unavailable. Refresh before deciding when to leave.") }
        let arrivals = visible(snapshot, now: now)
        let required = TimeInterval((trip.walkingMinutes + trip.bufferMinutes) * 60)
        guard let target = arrivals.first(where: { $0.predictedAt.timeIntervalSince(now) >= required }) else {
            if arrivals.contains(where: \.finalScheduled) { return unavailable("The final scheduled bus is too close for your walk and buffer. Check other transport options.") }
            return unavailable(arrivals.isEmpty ? "No usable predictions. This does not mean service has ended." : "The visible buses are too close for your walk and buffer. Waiting for another prediction.")
        }
        let departure = target.predictedAt.addingTimeInterval(-required)
        let seconds = departure.timeIntervalSince(now)
        let skipped = arrivals.first?.id != target.id
        let minutes = Int(floor(seconds / 60))
        let title = seconds < 60 ? (target.finalScheduled ? "Last chance — go now" : "Go now") : "Wait \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        var explanation = skipped ? "The next bus is too close for your walk and buffer. Aim for the following bus." : "Allow \(trip.walkingMinutes) min to walk + \(trip.bufferMinutes) min buffer."
        if target.finalScheduled { explanation += " Final scheduled bus for this service day; confirmed from the schedule." }
        return .init(title: title, explanation: explanation, departureAt: departure, arrivalID: target.id)
    }
}

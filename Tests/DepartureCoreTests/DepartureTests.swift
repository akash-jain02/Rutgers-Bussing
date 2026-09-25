#if !CORE_CLI_TESTS && canImport(XCTest)
import XCTest
#else
import Foundation
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \(b), got \(a)", file: file, line: line) }
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil", file: file, line: line) }
#endif
#if !CORE_CLI_TESTS
@testable import DepartureCore
#endif
final class DepartureTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var trip: SavedTrip { .init(routeID: "r", routeName: "LX", stopID: "s", stopName: "Yard", walkingMinutes: 5, bufferMinutes: 2) }
    func snapshot(_ offsets: [Double], age: Double = 0, final: Bool = false) -> Snapshot {
        .init(routeID: "r", stopID: "s", source: "live", updatedAt: now.addingTimeInterval(-age), arrivals: offsets.enumerated().map { .init(id: String($0.offset), predictedAt: now.addingTimeInterval($0.element), observedAt: now.addingTimeInterval(-age), finalScheduled: final) })
    }
    func testSubtractsWalkAndBuffer() {
        let r = DepartureEngine.recommend(trip: trip, snapshot: snapshot([1020, 1800]), now: now)
        XCTAssertEqual(r.title, "Wait 10 minutes")
        XCTAssertEqual(r.departureAt, now.addingTimeInterval(600))
    }
    func testTooCloseUsesFollowingBus() {
        let r = DepartureEngine.recommend(trip: trip, snapshot: snapshot([120, 1020]), now: now)
        XCTAssertEqual(r.arrivalID, "1"); XCTAssertTrue(r.explanation.contains("too close"))
    }
    func testExactBoundaryIsCatchable() { XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: snapshot([420]), now: now).title, "Go now") }
    func testOneSecondTooCloseIsNotCatchable() { XCTAssertNil(DepartureEngine.recommend(trip: trip, snapshot: snapshot([419]), now: now).arrivalID) }
    func testLessThanMinuteSaysGo() { XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: snapshot([479]), now: now).title, "Go now") }
    func testConservativeMinuteRounding() { XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: snapshot([539]), now: now).title, "Wait 1 minute") }
    func testDelayedPredictionMovesDeparture() {
        let first = DepartureEngine.recommend(trip: trip, snapshot: snapshot([1020]), now: now)
        let delayed = DepartureEngine.recommend(trip: trip, snapshot: snapshot([1320]), now: now)
        XCTAssertEqual(delayed.departureAt!.timeIntervalSince(first.departureAt!), 300)
    }
    func testMissingPredictionsNeverMeansLastChance() {
        for data in [nil, snapshot([])] {
            XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: data, now: now).title, "Check arrivals")
        }
    }
    func testStaleAndFutureDataBlocked() {
        for age in [91.0, -31.0] {
            XCTAssertNil(DepartureEngine.recommend(trip: trip, snapshot: snapshot([1020], age: age), now: now).arrivalID)
        }
    }
    func testPerTripStalenessBlocked() {
        var data = snapshot([1020]); data.arrivals[0].observedAt = now.addingTimeInterval(-100)
        XCTAssertNil(DepartureEngine.recommend(trip: trip, snapshot: data, now: now).arrivalID)
    }
    func testVerifiedFinalBus() {
        XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: snapshot([450], final: true), now: now).title, "Last chance — go now")
        XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: snapshot([1020], final: true), now: now).title, "Wait 10 minutes")
    }
    func testSingleArrivalIsNotFinal() { XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: snapshot([450]), now: now).title, "Go now") }
    func testMissedFinalDoesNotTellUserToRun() { XCTAssertNil(DepartureEngine.recommend(trip: trip, snapshot: snapshot([300], final: true), now: now).arrivalID) }
    func testMismatchedTripBlocked() {
        var data = snapshot([1020]); data.stopID = "other"
        XCTAssertNil(DepartureEngine.recommend(trip: trip, snapshot: data, now: now).arrivalID)
    }
    func testSortingAndExpiredPredictions() {
        let data = snapshot([1020, -50, 450])
        XCTAssertEqual(DepartureEngine.visible(data, now: now).map(\.id), ["2", "0"])
    }
    func testInvalidWalkingTime() {
        var value = trip; value.walkingMinutes = -1
        XCTAssertNil(DepartureEngine.recommend(trip: value, snapshot: snapshot([450]), now: now).arrivalID)
    }
    func testMidnightUsesAbsoluteTime() {
        let late = Date(timeIntervalSince1970: 1_790_006_380)
        let data = Snapshot(routeID: "r", stopID: "s", source: "live", updatedAt: late, arrivals: [.init(id: "a", predictedAt: late.addingTimeInterval(1020), observedAt: late)])
        XCTAssertEqual(DepartureEngine.recommend(trip: trip, snapshot: data, now: late).departureAt, late.addingTimeInterval(600))
    }
}

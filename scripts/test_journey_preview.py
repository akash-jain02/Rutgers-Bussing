"""Compile and check the Bus Concept journey fixtures without an iOS SDK."""
import pathlib
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[1]
source = '''
import Foundation
let now = Date(timeIntervalSince1970: 1_790_000_000)
func campus(_ id: String) -> CampusChoice { CampusChoice.named(id)! }
func minutes(_ p: JourneyPreview) -> [Int] { p.steps.map { Int($0.at.timeIntervalSince(p.createdAt) / 60) } }
let dt = HomePreference(campusID: "dt", stop: "Rockoff Hall", walk: 7, buffer: 2)

// Downtown -> Livingston reverses livi>dt: EE then LX, transfer at College Ave.
let trip = JourneyPreview.options(home: dt, destination: campus("livi"), now: now)
precondition(trip.map(\\.pace) == [.hurry, .steady, .wait])
precondition(trip.map(\\.recommended) == [false, true, false])
precondition(trip[0].boardings.map { $0.route! } == ["EE", "LX"])
precondition(trip[0].steps.contains { $0.title == "Get off at College Ave Student Center" })
precondition(trip[0].steps.last!.title == "Arrive at Livingston Student Center")
// Hand-computed from the design: board = walk+1+i*gap, transfer wait = 2+(t+i)%max(3,headway-2).
precondition(minutes(trip[0]) == [0, 8, 14, 18, 28])
precondition(minutes(trip[1]) == [9, 18, 24, 27, 37])
precondition(minutes(trip[2]) == [19, 28, 34, 36, 46])
precondition(trip[0].leaveAt == now && trip[0].totalMinutes == 28)
precondition(trip.map(\\.note) == ["Brisk walk, no buffer", "2 min to spare", "Relax first"])

// Direct trips have no transfer; alternates rotate per pace.
let direct = JourneyPreview.options(home: HomePreference(campusID: "ca", stop: "Scott Hall", walk: 5, buffer: 0), destination: campus("livi"), now: now)
precondition(direct[1].steps.count == 3 && direct[1].note == "Normal walk")
let busch = JourneyPreview.options(home: HomePreference(campusID: "busch", stop: "Hill Center", walk: 5, buffer: 2), destination: campus("dt"), now: now)
precondition(busch.map { $0.boardings[0].route! } == ["H", "A", "H"])
precondition(JourneyPreview.legs(from: "dt", to: "busch").map(\\.routes) == [["EE"], ["H", "A"]])

// Countdown, next step and expiry.
precondition(trip[1].secondsToLeave(at: now) == 540)
precondition(trip[0].secondsToLeave(at: now) == nil)
precondition(trip[1].nextStep(at: now.addingTimeInterval(10 * 60)).title == "Board the EE")
precondition(trip[1].isActive(at: trip[1].arriveAt))
precondition(!trip[1].isActive(at: trip[1].arriveAt.addingTimeInterval(1)))

// Clock matches the design: no leading zero, no AM/PM, 12 for midnight/noon.
func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: h, minute: m))! }
precondition(at(13, 5).clock == "1:05" && at(0, 0).clock == "12:00" && at(12, 30).clock == "12:30" && at(9, 40).clock == "9:40")

let restored = try JSONDecoder().decode(JourneyPreview.self, from: JSONEncoder().encode(trip[1]))
precondition(restored.id == trip[1].id && restored.pace == .steady && restored.steps.count == 5)
print("Journey checks passed: paces, timings, transfers, alternates, countdown, expiry, serialization")
'''
with tempfile.TemporaryDirectory(prefix='journey-checks-') as folder:
    folder = pathlib.Path(folder)
    (folder/'main.swift').write_text(source)
    subprocess.run(['swiftc', '-module-cache-path', str(folder/'cache'), str(root/'Apps/Shared/JourneyPreview.swift'), str(folder/'main.swift'), '-o', str(folder/'checks')], check=True)
    subprocess.run([str(folder/'checks')], check=True)

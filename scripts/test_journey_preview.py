"""Compile and check the journey-screen fixtures without an iOS SDK."""
import pathlib
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[1]
source = '''
import Foundation
let now = Date(timeIntervalSince1970: 1_790_000_000)
let livi = CampusChoice.all.first { $0.id == "livi" }!
let downtown = CampusChoice.all.first { $0.id == "dt" }!
let outbound = JourneyPreview.options(home: HomePreference(campusID: "dt", stop: "SoCam", walk: 7, buffer: 4), destination: livi, stop: livi.stops[0], now: now)
let inbound = JourneyPreview.options(home: HomePreference(campusID: "livi", stop: livi.stops[0], walk: 7, buffer: 4), destination: downtown, stop: downtown.stops[0], now: now)
precondition(outbound.count == 3)
precondition(outbound[0].steps.contains { $0.title == "Transfer at Student Activities Center" })
precondition(inbound[0].steps.contains { $0.title == "Transfer at College Avenue Student Center" })
for option in outbound {
    let board = option.steps.first { $0.route != nil }!
    precondition(board.at.timeIntervalSince(option.leaveAt) == 11 * 60)
    precondition(option.arriveAt > option.leaveAt)
    precondition(option.recommendation(at: now.addingTimeInterval(91)) == "Refresh options")
}
precondition(outbound[0].recommendation(at: now) == "Go now")
precondition(outbound[0].recommendation(at: now.addingTimeInterval(31)) == "Choose another departure")
// Two-leg timeline: walk+buffer 11 min, EE 12 min, transfer 5 min, LX 12 min.
let offsets = outbound[0].steps.map { Int($0.at.timeIntervalSince(outbound[0].leaveAt)) }
precondition(offsets == [0, 660, 1380, 1680, 2400])
precondition(outbound[0].arriveAt.timeIntervalSince(outbound[0].leaveAt) == 2400)
// Watch falls back to live departures once a preview is stale or its departure has passed.
precondition(outbound[1].isActive(at: now))
precondition(!outbound[1].isActive(at: now.addingTimeInterval(91)))
precondition(!outbound[0].isActive(at: now.addingTimeInterval(31)))
let encoded = try JSONEncoder().encode(outbound[1])
let restored = try JSONDecoder().decode(JourneyPreview.self, from: encoded)
precondition(restored.id == outbound[1].id)
precondition(restored.steps.count == outbound[1].steps.count)
print("Journey preview checks passed: directional transfers, walk/buffer, expiry, missed departure, and serialization")
'''
with tempfile.TemporaryDirectory(prefix='journey-checks-') as folder:
    folder = pathlib.Path(folder)
    (folder/'main.swift').write_text(source)
    subprocess.run(['swiftc', '-module-cache-path', str(folder/'cache'), str(root/'Apps/Shared/JourneyPreview.swift'), str(folder/'main.swift'), '-o', str(folder/'checks')], check=True)
    subprocess.run([str(folder/'checks')], check=True)

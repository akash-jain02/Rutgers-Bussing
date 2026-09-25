# Validation record

September 25, 2026.

## Completed

- Public static GTFS, GTFS-RT trip updates, and service-alert downloads returned HTTP 200 without credentials; decoded ZIP and Protobuf contents checked. See `feed-check.json`.
- Recorded live dataset: 22 routes, 54 stops, 3,134 static trips; 453 realtime entities, 452 exact static trip matches. Sample LX stop normalization produced six upcoming estimates using the recorded observation time.
- **17 Swift timing tests passed** using `python3 scripts/test_core.py`. This compiles the real calculator with the same test methods used by the XCTest suite and executes all of them using assertions.
- **23 Python tests passed** using `backend/.venv/bin/python -m pytest backend/tests -q`. Includes HTTP contract/failure tests via FastAPI TestClient. One upstream Starlette deprecation warning concerns its test-client HTTP dependency; tests pass.
- Swift source syntax parsed for phone, watch, and shared files with `swiftc -frontend -parse`.
- Generated Xcode project and both Info.plists pass `plutil -lint`.

## Not completed on this machine

Full Xcode is not installed. `xcodebuild -version` reports that the active developer directory is CommandLineTools. Standard `swift test` compiled DepartureCore, then failed because XCTest is absent. The standalone test runner was used to execute the same timing tests instead.

Neither app target has been compiled against the iOS/watchOS SDK, launched, or visually inspected in Simulator. Syntax validation is not type checking. No claim is made that signing, embedding, device pairing, or WatchConnectivity delivery has been verified. No AWS deployment or production release was performed.

## Xcode acceptance checks

1. Build both schemes on supported simulator runtimes, then verify watch installation with the phone companion. For devices, set signing and matching bundle identifiers first.
2. Launch a fresh install. Verify walking time is blank/required, invalid times cannot be saved, and changing routes resets an incompatible stop. Save, kill, and relaunch; verify persistence.
3. Exercise every demo scenario. For a 5-minute walk and 2-minute buffer, a bus 7 minutes away is catchable now; one 6:59 away must be skipped. A single unverified arrival must never become “Last chance.”
4. Switch to a local backend, select a real route/stop, and check arrival/update times against official TripShot. Ensure demo labels disappear only after live mode is explicitly selected.
5. Disconnect networking. Verify unavailable/error states and that no stale prediction stays usable after 90 seconds. Inspect the service-alert failure message independently of ETA availability.
6. Save a changed walking time on the phone while the watch is open. Verify both devices agree. Disconnect the watch, wait beyond 90 seconds, and confirm that it stops giving a departure recommendation.
7. Test large Dynamic Type, VoiceOver reading order, dark/light mode, and the smallest supported watch screen. Test after overnight service and foreground resume.

Any issues found by these checks should be resolved before distribution.

# Rutgers Departure

A native SwiftUI iPhone app and Apple Watch companion that answer **when should I leave for my bus?** The first launch uses clearly labeled demo data; real Rutgers TripShot integration is available through a small FastAPI adapter. No account or location permission is needed.

## Run the iPhone app

1. Install **Xcode 15 or newer** with iOS 17+ and watchOS 10+ SDKs and simulator runtimes. This development machine currently has Command Line Tools only, so the app targets have not been built or run in Simulator here.
2. Open **RutgersDeparture.xcodeproj** in Xcode. The project is checked in; no XcodeGen, CocoaPods, or external Swift package is required.
3. Choose the **RutgersDeparture** scheme and an iPhone Simulator. Press **⌘R**. Simulator builds do not need a paid Apple developer account.
4. Tap **Set up home**. Choose a campus and stop, enter your average walking time, and choose an optional buffer. Walking time is required, not silently assumed.
5. Choose a destination campus and stop, then inspect **Earliest**, **Recommended**, and **Later** departures. All three use your normal walking time and full buffer. Open a departure to see its timeline and send the preview to the watch.
6. The new journey screens are **demo only**: route combinations, rides, and transfers are simulated. EE → LX previews transfer at Student Activities Center; LX → EE previews transfer at College Avenue Student Center. These are separate directional fixtures, pending live verification.
7. Tap **Live arrivals** to open the existing route/stop arrival screen and its Data source settings. This retains its separate saved trip and live backend integration. Demo/live source labels remain visible. The journey preview does not replace the live route planner, which is not implemented yet.

For a physical iPhone, select your signing team for both targets. Change both bundle identifiers to your own unique identifiers, and update `WKCompanionAppBundleIdentifier` in `Apps/Watch/Info.plist` to match the phone target. These identifiers are placeholders, not Rutgers affiliation.

## Run the watch companion

1. In Xcode, configure an Apple Watch Simulator paired to your iPhone Simulator, or use a paired physical watch/phone with development enabled.
2. Run **RutgersDeparture** on the phone first and save a trip.
3. Select **RutgersDepartureWatch**, choose the paired watch destination, and run it. Open both apps to activate WatchConnectivity.
4. The phone sends the saved trip and latest snapshot through `updateApplicationContext`. The watch persists the last state and uses the same calculator. It shows the stop, next arrival, recommendation, alerts, and update time.
5. **Refresh from iPhone** requests an update when the phone app is reachable. A disconnected watch never resets the data timestamp; after 90 seconds it shows unavailable/outdated data instead of travel advice.

There is no background delivery guarantee, independent watch network provider, complication, or push notification in this version. Paired-device WatchConnectivity and installation still need verification in Xcode.

## Use real TripShot estimates locally

Access investigation and restrictions are documented in [docs/DATA_ACCESS.md](docs/DATA_ACCESS.md). The feeds returned HTTP 200 without authentication during the recorded check, but a feed-specific license and permitted request rate have **not** been established. Clarify production usage with Rutgers/TripShot before distribution.

From this directory:

```sh
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements.txt
backend/.venv/bin/python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
```

In the iPhone app, open **Live arrivals → Data source**, turn off **Use demo data**, set `http://localhost:8000` for Simulator, and tap **Apply**. Then select a real route and stop in **Edit trip**. Changing data sources clears the saved trip to avoid mixing demo IDs with live IDs.

On a physical phone, use your Mac's Bonjour hostname, e.g. `http://your-mac.local:8000`, on the same network, and allow the app's local-network prompt. `localhost` on a phone means that phone. The app allows local networking only; public deployments must use HTTPS. Backend API docs are available at `http://localhost:8000/docs`.

The phone refreshes every 30 seconds while active and on foreground entry. The backend shares a 20-second real-time cache and a six-hour static schedule cache per process. It returns 503 on upstream failure instead of inventing predictions. No server is needed for demo mode.

## Tests

```sh
# Full Xcode toolchain: shared calculation tests
swift test

# Command Line Tools fallback: runs the same 17 edge-case methods
python3 scripts/test_core.py

# Backend normalization and HTTP contract tests; no network required
backend/.venv/bin/python -m pytest backend/tests -q

# Optional read-only access check (network required)
backend/.venv/bin/python -m scripts.probe_feeds
```

The Python tests cover schedule calendars/exceptions, >24-hour service times, frequency-service uncertainty, stale/future feed timestamps, cancellations, skipped/no-data stops, delayed arrivals, unknown trip IDs, alerts, and HTTP failures. Swift tests cover walk/buffer arithmetic, catchability boundaries, conservative rounding, selecting the following bus, missing/stale data, final service, and mismatched snapshots.

`swift test` needs XCTest supplied by full Xcode. If Command Line Tools are selected after installing Xcode, select Xcode under **Xcode → Settings → Locations → Command Line Tools**.

## Files and architecture

- `Sources/DepartureCore/Departure.swift`: platform-independent models and pure clock-injected calculator.
- `Apps/iOS/RutgersDepartureApp.swift`: phone home, route/stop/walking-time setup, data-source configuration.
- `Apps/Shared/TripStore.swift`: persistence, demo scenarios, live HTTP adapter, foreground refresh, WatchConnectivity.
- `Apps/Shared/DepartureView.swift`: shared accessible SwiftUI departure and arrival display.
- `Apps/Watch/RutgersDepartureWatchApp.swift`: glanceable companion.
- `backend/transit.py`: static GTFS and GTFS-RT parsing, conservative final-service verification, scoped alerts.
- `backend/app.py`: `/catalog`, `/arrivals`, `/health`; cached feed access.
- `Tests/DepartureCoreTests` and `backend/tests`: deterministic tests.
- `scripts/generate_project.py`: reproducible Xcode project and Info.plist generator. Regeneration overwrites project settings and placeholder identifiers; preserve signing changes separately.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): timing rules, reliability choices, and limitations.
- [docs/VALIDATION.md](docs/VALIDATION.md): what was actually checked and the remaining device acceptance checklist.

## Remaining production work

- Confirm feed permissions, redistribution terms, rate limits, endpoint stability, and Rutgers region coverage.
- Build and run both app targets in Xcode; validate phone/watch sync, Dynamic Type, VoiceOver, light/dark appearance, and network transitions on devices.
- Add app icons, production bundle IDs, signing, privacy/support links, and App Store metadata. No Rutgers trademarks/assets are bundled.
- For a hosted version, use **AWS Lambda** with an ASGI adapter such as Mangum, API Gateway HTTPS, deployment packaging, observability, throttling, and a shared schedule/feed cache (e.g. S3). A cold Lambda instance fetching/parsing the large schedule on demand needs a cache/preload design. No cloud resources were deployed or billed.
- Add background notifications only with opt-in and a strategy for changing ETAs and stale data. The current version sends no notifications.
- Extend support for frequency-based trips, missing absolute arrival times, ambiguous/unmatched trip IDs, and richer alert actions only after their data semantics are verified. These cases currently fail conservatively instead of guessing.

## New journey-screen implementation

`Apps/iOS/JourneyScreens.swift` contains home setup, destination-stop selection, options, and trip detail. `Apps/Shared/JourneyPreview.swift` defines clearly labeled fixture journeys. The watch receives the selected preview via WatchConnectivity; destination selection still happens on iPhone. Journey previews expire after 90 seconds and stop recommending departure once the leave-by time has passed. Home settings are persisted separately from the existing saved live trip. Native system fonts and semantic surfaces approximate the supplied design while supporting Dynamic Type and dark appearance.

Run `python3 scripts/test_journey_preview.py` to check asymmetric transfer fixtures, walking/buffer arithmetic, expired/missed departures, and serialization. Full iOS/watchOS builds and visual verification still require Xcode.

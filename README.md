# Rutgers Departure

SwiftUI iPhone and Apple Watch apps that recommend when to leave for a Rutgers bus stop using live TripShot estimates, your average walking time, and an optional safety buffer.

## Run in Xcode

Open `RutgersDeparture.xcodeproj`, choose the RutgersDeparture scheme and an iPhone simulator, and run. Xcode with iOS 17+ and watchOS 10+ SDKs is required. For physical devices, configure your signing team and matching phone/watch bundle identifiers.

The app defaults to:

https://rutty-api.prouddune-2c1f0d5b.canadacentral.azurecontainerapps.io

Tap **Set up my trip**, select a route and stop from the API, enter your average walking time, and save. The Departures screen shows the next two predictions, recommendation, alerts, and source update time. Data source settings allow changing the backend address. Cold starts may take several seconds; requests allow up to 60 seconds.

There is no demo mode or simulated arrival fallback. Upgrading clears legacy demo trips and switches the endpoint to Azure once; real saved route/stop selections are retained. Subsequent custom endpoint settings are preserved. Update both phone and watch apps together.

## Journeys and watch

Destination and transfer routing are not yet implemented against verified live data. The Journeys tab displays an unavailable message instead of invented routes or travel times. Direction-specific transfer rules, including EE → LX versus LX → EE, still need live verification and implementation.

The watch receives the saved trip and snapshot from iPhone via WatchConnectivity, displays the same recommendation, and can request a refresh when the phone is reachable. Predictions expire after 90 seconds; source timestamps are never replaced with watch delivery times.

## Backend

FastAPI decodes static GTFS and GTFS-RT, maps route/stop IDs, filters alerts, and conservatively identifies final scheduled pickups. `/health` checks server liveness, `/catalog` returns routes/stops, and `/arrivals` provides timestamped estimates. A successful health check alone does not verify upstream feeds.

For local development:

```sh
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements.txt
backend/.venv/bin/python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
```

Set the Simulator endpoint to `http://localhost:8000`; physical devices need your Mac's reachable local hostname or the deployed HTTPS URL.

## Checks and limitations

```sh
swift test
# Command Line Tools fallback:
python3 scripts/test_core.py
backend/.venv/bin/python -m pytest backend/tests -q
```

The calculator rejects stale/non-live data, skips buses too close for the walk plus buffer, and never infers a final bus from prediction count. Tests use synthetic fixtures only; they are not app data providers.

Full iOS/watchOS builds and paired-device testing remain necessary. Push notifications, background polling guarantees, and independent watch networking are not implemented. Feed rights and access restrictions are documented in `docs/DATA_ACCESS.md`. Earlier design/validation documents describe historical demo versions; the current application is live-only.

## Docker

See [Docker setup](docs/DOCKER.md) for the Dockerfile and optional Compose workflow. Containers package only the backend; the Apple apps require Xcode. The default local container port is 8001. Azure deployments require a built registry image and appropriate HTTPS ingress; pushing app code to GitHub does not redeploy Azure.

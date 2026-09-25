# Architecture and behavioral contract

## Smallest implementation

The iPhone is the trip owner. It persists one route/stop/walk/buffer combination in UserDefaults. It fetches normalized JSON when live mode is selected, or generates explicitly marked demo snapshots. WatchConnectivity transfers the full saved trip plus snapshot to the companion; both use identical pure Swift calculation code. No login, GPS, database, or cloud deployment is needed for the first version.

FastAPI adds value by decoding Protobuf, joining static schedule IDs to routes/stops, filtering alerts, and verifying final scheduled pickups. Apple clients do not need ZIP/CSV/Protobuf libraries or a 57 MB expanded schedule. Network access is centralized and cached per backend worker.

## Departure policy

`leaveAt = predictedAt - walkingMinutes * 60 - bufferMinutes * 60`

Catchable means `leaveAt >= now`. The buffer is part of the user's required lead time; a bus that could be caught only by sacrificing it is treated as too close. The earliest catchable fresh prediction becomes the target. Up to eight future estimates may be normalized so later candidates can be chosen even when the visible first two are too close.

- At least 60 seconds until leaveAt: “Wait X minutes,” rounding **down**, plus the exact leave-by clock time.
- Less than 60 seconds: “Go now.” This deliberately sends the student slightly early.
- Same immediate window plus verified final scheduled pickup: “Last chance — go now.”
- If the first arrival is too close, the explanation says the recommendation targets a following bus.
- If no candidate is catchable, show “Check arrivals,” with an explanation. Never encourage running for an already missed final bus.
- A final bus farther away still says “Wait X minutes” with a final-service explanation.

Final means the last scheduled pickup at the chosen route/stop for the trip's GTFS service day, including times beyond 24:00 and calendar exceptions. It is not a claim that service will never operate again. Frequency trips, tied final visits, expired schedules, missing service dates, unmatched real-time trip IDs, and relevant alerts prevent a final label. Canceled final trips are not reassigned to another bus without adequate evidence.

## Reliability

Freshness uses the GTFS-RT header timestamp and the older of that timestamp and the trip's timestamp. App fetch time and watch delivery time never replace these values. Both platforms reject data older than 90 seconds and tolerate at most 30 seconds of future clock skew. Predicted arrivals in the past are removed. The UI recalculates as time advances, even without a network response.

There is no silent source switching. A live network failure produces an unavailable state, not invented arrivals. Static and real-time fetches use bounded timeouts. A missing alert feed is visible. The backend only accepts FULL_DATASET feeds; differential updates require stateful handling not implemented here.

HTTP JSON dates are Unix seconds. The phone validates route ID, stop ID, and live/demo source before publishing data. User input allows 1–120 walking minutes and 0–30 buffer minutes. Snapshot IDs prevent accidentally applying a response for one stop to another.

## Watch constraints

Watch application context is eventual delivery, not a push notification or guaranteed background polling channel. The watch keeps the original observation timestamps. It can request a phone refresh when reachable, but cannot fetch independently. Setup and changing walking time happen on iPhone. Test on paired physical devices before release; simulator WatchConnectivity can differ from real devices.

## Intentional omissions

No push notifications, background ETA tracking, widgets/complications, geolocation-derived walking times, trip planner, multiple saved trips, user accounts, or AWS deployment. App icon and release metadata remain production configuration. Future AWS hosting should use Lambda as requested, with shared caching to avoid each cold instance repeatedly fetching the large static feed.

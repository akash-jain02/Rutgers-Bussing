# Rutgers TripShot access investigation

Checked September 25, 2026, approximately 15:55–15:56 UTC. Evidence is summarized in [feed-check.json](feed-check.json). This is a point-in-time observation, not a guarantee of future availability.

## Authoritative sources

- [Rutgers transition announcement](https://ipo.rutgers.edu/transportation/new-transit-tracking-tripshot) names TripShot as the official platform.
- [Rutgers bus information](https://construction.rutgers.edu/transportation/buses/nb) links to the [Rutgers TripShot rider site](https://rutgers.tripshot.com), which redirects to `/g/tms/Public.html`.
- [TripShot GTFS support](https://tripshot.com/ebooks/supporting-gtfsgtfs-rt-for-more-reliable-transportation) confirms support for GTFS and GTFS-RT. It does not establish public API rights for this particular tenant.
- [TripShot terms](https://tripshot.com/terms-of-service), dated November 1, 2021, include general restrictions on automated access in §8.4 and on use of materials in §5. No Rutgers-specific feed license, authorization procedure, SLA, or rate-limit policy was found. Public reachability alone does not resolve those restrictions. Request clarification from Rutgers DOTS/TripShot before production redistribution.
- Parsing follows the [GTFS schedule reference](https://gtfs.org/documentation/schedule/reference/) and [GTFS Realtime reference](https://gtfs.org/documentation/realtime/reference/).

Candidate URLs were discovered through search, then checked directly against Rutgers' TripShot host. They are not inferred API routes. The implementation uses only the three verified URLs below. The browser research tool could not open their binary formats, so verification used HTTPS downloads and ZIP/Protobuf decoding.

## Verified resources

Tenant region: `CA558DDC-D7F2-4B48-9CAC-DEEA1134F820`.

| Data | Verified URL | Observed result |
|---|---|---|
| Routes, stops, trips, schedules | `https://rutgers.tripshot.com/v1/gtfs.zip?regionId=CA558DDC-D7F2-4B48-9CAC-DEEA1134F820` | HTTP 200, ZIP containing routes, stops, trips, stop_times, calendar, calendar_dates, agency, shapes, frequencies, feed_info |
| Arrival estimates | `https://rutgers.tripshot.com/v1/gtfs/realtime/tripUpdate/CA558DDC-D7F2-4B48-9CAC-DEEA1134F820` | HTTP 200, decoded GTFS-RT 2.0 FULL_DATASET, 453 entities, absolute arrival timestamps and per-trip timestamps |
| Service alerts | `https://rutgers.tripshot.com/v1/gtfs/realtime/serviceAlert/CA558DDC-D7F2-4B48-9CAC-DEEA1134F820` | HTTP 200, valid GTFS-RT 2.0 feed, zero active entities in this sample |

No API key, login, cookies, private account, or authorization header was used. No access controls were bypassed. Vehicle positions were not needed or investigated. An empty alert feed verifies access and format, but does not prove the source reports every real-world disruption.

The schedule contains 22 routes, including services beyond the main New Brunswick campus, and uses `America/New_York`. 452 of the 453 sampled trip IDs matched the static schedule exactly. The normalizer does not strip suffixes or guess at unmatched IDs. Sample LX route/stop normalization yielded six upcoming entries using the **recorded feed time** for validation; that saved sample is not shipped as live data.

The feed contains some frequency-based trips. Static schedules can extend past 24:00, and service exceptions exist. The adapter marks a final bus only for an unambiguous scheduled pickup on the declared service day, with fresh schedules/real-time feeds, no relevant alert, no unmatched update in the snapshot, and no active frequency-based service for that route/stop/day. These conservative conditions can suppress final-service labels even when a human could establish that service is ending.

## Limits of the observation

The backend consumes the producer's estimates; it cannot independently verify that every GTFS-RT timestamp is based on fresh GPS rather than a schedule projection. It preserves source timestamps, never promotes static stop times into live ETAs, and rejects data older than 90 seconds or more than 30 seconds into the future. Delay-only updates and unknown static mappings are omitted rather than fabricated.

Fresh valid feeds with zero usable arrivals are displayed as unavailable predictions, never “service ended.” A failed alert fetch is visibly marked, rather than being represented as no disruptions. Feed outages do not fall back silently to demo data. Demo selection is explicit and labeled on both devices.

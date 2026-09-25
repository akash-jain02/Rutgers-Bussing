"""Read-only feed verification; run from the repository root using backend/.venv/bin/python."""
import asyncio
import json
import time
import httpx
from backend.transit import URLS, Schedule, decode

async def main():
    results = {}
    async with httpx.AsyncClient(timeout=60, follow_redirects=True) as client:
        for key, url in URLS.items():
            response = await client.get(url)
            response.raise_for_status()
            entry = {'url': url, 'status': response.status_code, 'content_type': response.headers.get('content-type')}
            if key == 'schedule':
                schedule = Schedule(response.content)
                entry['routes'] = len(schedule.catalog())
                entry['stops'] = len(schedule.stops)
                entry['trips'] = len(schedule.trips)
            else:
                feed = decode(response.content)
                entry.update(timestamp=feed.header.timestamp, age_seconds=round(time.time()-feed.header.timestamp), entities=len(feed.entity))
                if key == 'trips':
                    entry['matching_static_trips'] = sum(e.trip_update.trip.trip_id in schedule.trips for e in feed.entity if e.HasField('trip_update'))
            results[key] = entry
    print(json.dumps(results, indent=2))

if __name__ == '__main__': asyncio.run(main())

import asyncio
import time
import httpx
from fastapi import FastAPI, HTTPException
from backend.transit import URLS, Schedule, decode, normalize

app = FastAPI(title='Rutgers Departure', version='0.1.0')
cache = {}
lock = asyncio.Lock()

async def fetch(key, ttl):
    async with lock:
        if key in cache and time.time() - cache[key][0] < ttl: return cache[key][1]
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            response = await client.get(URLS[key])
            response.raise_for_status()
        value = Schedule(response.content) if key == 'schedule' else decode(response.content)
        cache[key] = (time.time(), value)
        return value

@app.get('/health')
def health(): return {'status': 'ok'}

@app.get('/catalog')
async def catalog():
    try: return (await fetch('schedule', 21600)).catalog()
    except Exception as exc: raise HTTPException(503, 'Rutgers schedule unavailable') from exc

@app.get('/arrivals')
async def arrivals(route_id: str, stop_id: str):
    try:
        schedule = await fetch('schedule', 21600)
        if (route_id, stop_id) not in schedule.by_route_stop: raise HTTPException(404, 'Route does not serve this stop')
        feed = await fetch('trips', 20)
        try: alerts = await fetch('alerts', 20)
        except Exception: alerts = None
        return normalize(schedule, feed, alerts, route_id, stop_id, time.time())
    except HTTPException: raise
    except Exception as exc: raise HTTPException(503, 'TripShot predictions unavailable; try again shortly') from exc

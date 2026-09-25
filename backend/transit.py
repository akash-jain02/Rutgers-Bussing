"""Rutgers GTFS normalization. No undocumented JSON API or fabricated ETAs."""
import csv
import io
import time
import zipfile
from datetime import datetime
from zoneinfo import ZoneInfo
from google.transit import gtfs_realtime_pb2 as pb

REGION = 'CA558DDC-D7F2-4B48-9CAC-DEEA1134F820'
BASE = 'https://rutgers.tripshot.com/v1'
URLS = {'schedule': f'{BASE}/gtfs.zip?regionId={REGION}',
        'trips': f'{BASE}/gtfs/realtime/tripUpdate/{REGION}',
        'alerts': f'{BASE}/gtfs/realtime/serviceAlert/{REGION}'}
MAX_AGE = 90

def fresh(stamp, now):
    return bool(stamp) and -30 <= now - stamp <= MAX_AGE

def seconds(value):
    h, m, s = map(int, value.split(':'))
    return h * 3600 + m * 60 + s

class Schedule:
    def __init__(self, data, loaded_at=None):
        self.loaded_at = loaded_at or time.time()
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            def rows(name):
                if name not in archive.namelist(): return []
                return list(csv.DictReader(io.StringIO(archive.read(name).decode('utf-8-sig'))))
            self.routes = {r['route_id']: r for r in rows('routes.txt')}
            self.stops = {s['stop_id']: s for s in rows('stops.txt')}
            self.trips = {t['trip_id']: t for t in rows('trips.txt')}
            self.calendar = {c['service_id']: c for c in rows('calendar.txt')}
            self.exceptions = {(c['service_id'], c['date']): c['exception_type'] for c in rows('calendar_dates.txt')}
            self.frequency = {r['trip_id'] for r in rows('frequencies.txt')}
            self.visits = {}
            self.by_route_stop = {}
            for row in rows('stop_times.txt'):
                trip = self.trips.get(row['trip_id'])
                if not trip or row.get('pickup_type') == '1': continue
                self.visits[(row['trip_id'], row['stop_sequence'])] = row
                self.by_route_stop.setdefault((trip['route_id'], row['stop_id']), []).append(row)

    def catalog(self):
        result = []
        for rid, route in self.routes.items():
            stops = [{'id': sid, 'name': self.stops[sid]['stop_name']} for r, sid in self.by_route_stop if r == rid and sid in self.stops]
            if stops: result.append({'id': rid, 'name': route['route_short_name'] or route['route_long_name'], 'stops': sorted(stops, key=lambda s: s['name'])})
        return sorted(result, key=lambda r: r['name'])

    def active(self, service, day):
        exception = self.exceptions.get((service, day))
        if exception: return exception == '1'
        cal = self.calendar.get(service)
        if not cal or not cal['start_date'] <= day <= cal['end_date']: return False
        weekday = datetime.strptime(day, '%Y%m%d').strftime('%A').lower()
        return cal[weekday] == '1'

    def final_visit(self, route, stop, day, now):
        # Never guess with old calendars or frequency-based service.
        if not day or now - self.loaded_at > 21600: return None
        try:
            rows = [r for r in self.by_route_stop.get((route, stop), []) if self.active(self.trips[r['trip_id']]['service_id'], day)]
            if not rows or any(r['trip_id'] in self.frequency or not r['arrival_time'] for r in rows): return None
            last = max(seconds(r['arrival_time']) for r in rows)
            finals = [r for r in rows if seconds(r['arrival_time']) == last]
            if len(finals) != 1: return None
            row = finals[0]
            return row['trip_id'], row['stop_sequence']
        except (ValueError, KeyError):
            return None


def decode(data):
    feed = pb.FeedMessage.FromString(data)
    if not feed.IsInitialized() or feed.header.incrementality != pb.FeedHeader.FULL_DATASET:
        raise ValueError('Invalid or differential feed; full snapshot required')
    return feed


def alert_messages(feed, route, stop, schedule, now):
    if feed is None or not fresh(feed.header.timestamp, now): return ['Service alerts are unavailable or outdated. Check TripShot.']
    messages = []
    for entity in feed.entity:
        if not entity.HasField('alert') or entity.is_deleted: continue
        a = entity.alert
        if a.active_period and not any((not p.HasField('start') or p.start <= now) and (not p.HasField('end') or now < p.end) for p in a.active_period): continue
        def applies(selector):
            if selector.route_id and selector.route_id != route: return False
            if selector.stop_id and selector.stop_id != stop: return False
            if selector.HasField('route_type') and selector.route_type != 3: return False
            if selector.HasField('trip'):
                trip_route = selector.trip.route_id or schedule.trips.get(selector.trip.trip_id, {}).get('route_id')
                if trip_route and trip_route != route: return False
            return True
        if a.informed_entity and not any(applies(s) for s in a.informed_entity): continue
        def english(text):
            return next((t.text for t in text.translation if t.language in ('en', '')), text.translation[0].text if text.translation else '')
        messages.append(' — '.join(filter(None, [english(a.header_text), english(a.description_text)])) or 'Service disruption reported. Check TripShot.')
    return messages


def normalize(schedule, feed, alerts, route, stop, now):
    messages = alert_messages(alerts, route, stop, schedule, now)
    result = {'routeID': route, 'stopID': stop, 'source': 'live', 'updatedAt': feed.header.timestamp or None,
              'arrivals': [], 'alerts': messages,
              'scheduleNote': 'Final means final scheduled pickup for the TripShot service day. Frequency service and uncertain matches are not marked final.'}
    if not fresh(feed.header.timestamp, now): return result
    # Unknown trips could represent additional service. Suppress final claims globally.
    complete = all(not e.HasField('trip_update') or e.trip_update.trip.trip_id in schedule.trips for e in feed.entity)
    final_cache = {}
    seen = set()
    for entity in feed.entity:
        if entity.is_deleted or not entity.HasField('trip_update'): continue
        update = entity.trip_update
        descriptor = update.trip
        trip = schedule.trips.get(descriptor.trip_id)
        if not trip or trip['route_id'] != route: continue
        if descriptor.schedule_relationship in (pb.TripDescriptor.CANCELED, pb.TripDescriptor.DELETED):
            messages.append('A trip on this route has been canceled.'); continue
        observed = min(update.timestamp or feed.header.timestamp, feed.header.timestamp)
        if not fresh(observed, now): continue
        for visit in update.stop_time_update:
            row = schedule.visits.get((descriptor.trip_id, str(visit.stop_sequence)))
            sid = visit.stop_id or (row['stop_id'] if row else '')
            if sid != stop or visit.schedule_relationship in (pb.TripUpdate.StopTimeUpdate.SKIPPED, pb.TripUpdate.StopTimeUpdate.NO_DATA): continue
            if row is None or row['stop_id'] != stop: continue
            # Absolute arrival time only: never turn a timetable into a live ETA.
            if not visit.HasField('arrival') or not visit.arrival.HasField('time'): continue
            stamp = visit.arrival.time
            if stamp < now or stamp > now + 86400: continue
            identity = f'{descriptor.trip_id}:{descriptor.start_date}:{visit.stop_sequence}'
            if identity in seen: continue
            seen.add(identity)
            day = descriptor.start_date
            if day not in final_cache: final_cache[day] = schedule.final_visit(route, stop, day, now)
            final = (complete and not messages and descriptor.schedule_relationship == pb.TripDescriptor.SCHEDULED and
                     final_cache[day] == (descriptor.trip_id, str(visit.stop_sequence)))
            result['arrivals'].append({'id': identity, 'predictedAt': stamp, 'observedAt': observed, 'finalScheduled': bool(final)})
    result['arrivals'].sort(key=lambda a: a['predictedAt'])
    result['arrivals'] = result['arrivals'][:8]
    result['alerts'] = list(dict.fromkeys(messages))
    if result['alerts']:
        for arrival in result['arrivals']: arrival['finalScheduled'] = False
    return result

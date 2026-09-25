import csv
import io
import zipfile
from datetime import datetime, timezone
from google.transit import gtfs_realtime_pb2 as pb
from backend.transit import Schedule, normalize, decode

NOW = datetime(2026, 9, 25, 23, 40, tzinfo=timezone.utc).timestamp()
DAY = '20260925'

def schedule(frequency=False, exception=None, last_time='25:00:00'):
    tables = {
        'routes.txt': 'route_id,route_short_name,route_long_name\nr,LX,LX Route\n',
        'stops.txt': 'stop_id,stop_name\ns,Yard\n',
        'trips.txt': 'trip_id,route_id,service_id\na,r,weekday\nb,r,weekday\n',
        'calendar.txt': 'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nweekday,1,1,1,1,1,0,0,20260101,20261231\n',
        'stop_times.txt': f'trip_id,stop_id,stop_sequence,arrival_time,pickup_type\na,s,1,23:00:00,0\nb,s,1,{last_time},0\n',
        'frequencies.txt': 'trip_id,start_time,end_time,headway_secs,exact_times\n' + ('b,23:00:00,25:00:00,600,0\n' if frequency else ''),
        'calendar_dates.txt': 'service_id,date,exception_type\n' + (f'weekday,{DAY},{exception}\n' if exception else '')
    }
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as z:
        for name, text in tables.items(): z.writestr(name, text)
    return Schedule(output.getvalue(), NOW)

def feed(trip='b', age=0):
    f = pb.FeedMessage(); f.header.gtfs_realtime_version = '2.0'; f.header.timestamp = int(NOW - age)
    e = f.entity.add(); e.id = '1'; u = e.trip_update
    u.trip.trip_id = trip; u.trip.start_date = DAY; u.timestamp = int(NOW-age)
    v = u.stop_time_update.add(); v.stop_id = 's'; v.stop_sequence = 1; v.arrival.time = int(NOW+600)
    return f

def alerts():
    f = pb.FeedMessage(); f.header.gtfs_realtime_version = '2.0'; f.header.timestamp = int(NOW)
    return f

def result(s=None, f=None, a=None): return normalize(s or schedule(), f or feed(), a or alerts(), 'r', 's', NOW)

def test_real_schedule_final(): assert result()['arrivals'][0]['finalScheduled']
def test_one_prediction_is_not_final(): assert not result(f=feed('a'))['arrivals'][0]['finalScheduled']
def test_frequency_final_is_unknown(): assert not result(s=schedule(frequency=True))['arrivals'][0]['finalScheduled']
def test_calendar_removal(): assert not result(s=schedule(exception='2'))['arrivals'][0]['finalScheduled']
def test_calendar_addition(): assert schedule(exception='1').active('weekday', DAY)
def test_hours_beyond_midnight(): assert schedule().final_visit('r', 's', DAY, NOW) == ('b', '1')
def test_old_schedule():
    s = schedule(); s.loaded_at = NOW - 21601
    assert not result(s=s)['arrivals'][0]['finalScheduled']
def test_stale_feed(): assert result(f=feed(age=91))['arrivals'] == []
def test_future_feed(): assert result(f=feed(age=-31))['arrivals'] == []
def test_missing_timestamp():
    f = feed(); f.header.ClearField('timestamp')
    assert result(f=f)['arrivals'] == []
def test_old_trip_in_fresh_feed():
    f = feed(); f.entity[0].trip_update.timestamp = int(NOW-91)
    assert result(f=f)['arrivals'] == []
def test_canceled_and_skipped():
    f = feed(); f.entity[0].trip_update.trip.schedule_relationship = pb.TripDescriptor.CANCELED
    assert result(f=f)['arrivals'] == []
    f = feed(); f.entity[0].trip_update.stop_time_update[0].schedule_relationship = pb.TripUpdate.StopTimeUpdate.SKIPPED
    assert result(f=f)['arrivals'] == []
def test_no_data_is_not_prediction():
    f = feed(); f.entity[0].trip_update.stop_time_update[0].schedule_relationship = pb.TripUpdate.StopTimeUpdate.NO_DATA
    assert result(f=f)['arrivals'] == []
def test_delay_only_not_fabricated():
    f = feed(); v=f.entity[0].trip_update.stop_time_update[0]; v.arrival.ClearField('time'); v.arrival.delay=60
    assert result(f=f)['arrivals'] == []
def test_delayed_absolute_time():
    f = feed(); f.entity[0].trip_update.stop_time_update[0].arrival.time += 300
    assert result(f=f)['arrivals'][0]['predictedAt'] == NOW+900
def test_unknown_trip_suppresses_final():
    f = feed(); e=f.entity.add(); e.id='unknown'; e.trip_update.trip.trip_id='unknown'
    assert not result(f=f)['arrivals'][0]['finalScheduled']
def test_stop_mismatch_rejected():
    f = feed(); f.entity[0].trip_update.stop_time_update[0].stop_id = 'wrong'
    assert result(f=f)['arrivals'] == []
def test_alert_scoping_and_period():
    a = alerts(); e = a.entity.add(); e.id='alert'; alert=e.alert
    alert.header_text.translation.add(text='Detour', language='en')
    alert.informed_entity.add(route_id='other')
    assert result(a=a)['alerts'] == []
    alert.informed_entity[0].route_id='r'
    assert result(a=a)['alerts'] == ['Detour']
    assert not result(a=a)['arrivals'][0]['finalScheduled']
    alert.active_period.add(end=int(NOW-1))
    assert result(a=a)['alerts'] == []
def test_missing_alerts_suppresses_final():
    r = normalize(schedule(), feed(), None, 'r', 's', NOW)
    assert r['alerts'] and not r['arrivals'][0]['finalScheduled']
def test_differential_rejected():
    f = feed(); f.header.incrementality = pb.FeedHeader.DIFFERENTIAL
    import pytest
    with pytest.raises(ValueError): decode(f.SerializeToString())
def test_route_stop_catalog(): assert schedule().catalog() == [{'id':'r','name':'LX','stops':[{'id':'s','name':'Yard'}]}]

from fastapi.testclient import TestClient
from backend import app as module
from backend.tests.test_transit import schedule, feed, alerts

client = TestClient(module.app)

def test_catalog_and_arrival_contract(monkeypatch):
    async def fake(key, ttl): return {'schedule': schedule(), 'trips': feed(), 'alerts': alerts()}[key]
    monkeypatch.setattr(module, 'fetch', fake)
    response = client.get('/catalog')
    assert response.status_code == 200 and response.json()[0]['id'] == 'r'
    response = client.get('/arrivals', params={'route_id':'r','stop_id':'s'})
    assert response.status_code == 200
    assert set(response.json()) == {'routeID','stopID','source','updatedAt','arrivals','alerts','scheduleNote'}
    assert client.get('/arrivals', params={'route_id':'wrong','stop_id':'s'}).status_code == 404

def test_upstream_failure_is_unavailable(monkeypatch):
    async def fail(key, ttl): raise RuntimeError('offline')
    monkeypatch.setattr(module, 'fetch', fail)
    assert client.get('/catalog').status_code == 503
    assert client.get('/arrivals', params={'route_id':'r','stop_id':'s'}).status_code == 503

import os

os.environ['DEMO_PROCESSOR'] = 'true'

from fastapi.testclient import TestClient

from app.main import app
from app.credit_store import MemoryCreditStore


client = TestClient(app)


def test_wallet_starts_with_credits_and_disabled_provider() -> None:
    wallet = client.get('/api/v1/vehicle-lookups/wallet')
    assert wallet.status_code == 200
    assert wallet.json() == {
        'balance': 100,
        'initialCredits': 100,
        'lookupCost': 1,
        'provider': 'DataFlag',
        'configured': False,
    }

    lookup = client.post(
        '/api/v1/vehicle-lookups',
        json={'vehicleNumber': 'KA01AB1234'},
    )
    assert lookup.status_code == 503
    assert client.get('/api/v1/vehicle-lookups/wallet').json()['balance'] == 100

    ledger = client.get('/api/v1/vehicle-lookups/ledger')
    assert ledger.status_code == 200
    assert ledger.json()[0]['amount'] == 100


def test_successful_lookup_charge_is_recorded_once() -> None:
    store = MemoryCreditStore()
    entry = store.charge_lookup('KA01AB1234')

    assert entry is not None
    assert entry.amount == -1
    assert entry.balance_after == 99
    assert entry.vehicle_number == 'KA01AB1234'
    assert store.get_wallet(configured=True).balance == 99
    assert sorted(item.amount for item in store.list_ledger()) == [-1, 100]

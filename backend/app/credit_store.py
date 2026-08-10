from threading import RLock
from typing import Protocol

from azure.core.exceptions import ResourceNotFoundError
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

from .config import get_settings
from .vehicle_models import CreditLedgerEntry, CreditWallet

_SYSTEM_PARTITION = '_system'
_INITIAL_CREDITS = 100


class CreditStore(Protocol):
    def get_wallet(self, configured: bool) -> CreditWallet: ...

    def charge_lookup(self, vehicle_number: str) -> CreditLedgerEntry | None: ...

    def list_ledger(self) -> list[CreditLedgerEntry]: ...


class MemoryCreditStore:
    def __init__(self) -> None:
        self._balance = _INITIAL_CREDITS
        self._lock = RLock()
        self._ledger = [
            CreditLedgerEntry(
                id='LED-INITIAL',
                amount=_INITIAL_CREDITS,
                balanceAfter=_INITIAL_CREDITS,
                reason='Initial pilot allocation',
            )
        ]

    def get_wallet(self, configured: bool) -> CreditWallet:
        with self._lock:
            return CreditWallet(balance=self._balance, configured=configured)

    def charge_lookup(self, vehicle_number: str) -> CreditLedgerEntry | None:
        with self._lock:
            if self._balance < 1:
                return None
            self._balance -= 1
            entry = CreditLedgerEntry(
                amount=-1,
                balanceAfter=self._balance,
                reason='Vehicle registration lookup',
                vehicleNumber=vehicle_number,
                provider='DataFlag',
            )
            self._ledger.append(entry)
            return entry

    def list_ledger(self) -> list[CreditLedgerEntry]:
        with self._lock:
            return sorted(
                self._ledger,
                key=lambda entry: entry.created_at,
                reverse=True,
            )


class CosmosCreditStore:
    def __init__(self, endpoint: str, database: str) -> None:
        client = CosmosClient(endpoint, credential=DefaultAzureCredential())
        self._container = client.get_database_client(database).get_container_client(
            'operational'
        )
        self._lock = RLock()

    def _ensure_wallet(self) -> dict:
        try:
            return self._container.read_item(
                item='CREDIT-WALLET',
                partition_key=_SYSTEM_PARTITION,
            )
        except ResourceNotFoundError:
            wallet = {
                'id': 'CREDIT-WALLET',
                'camera': _SYSTEM_PARTITION,
                'documentType': 'creditWallet',
                'balance': _INITIAL_CREDITS,
                'initialCredits': _INITIAL_CREDITS,
            }
            self._container.create_item(wallet)
            initial = CreditLedgerEntry(
                id='LED-INITIAL',
                amount=_INITIAL_CREDITS,
                balanceAfter=_INITIAL_CREDITS,
                reason='Initial pilot allocation',
            )
            self._save_ledger(initial)
            return wallet

    def _save_ledger(self, entry: CreditLedgerEntry) -> None:
        item = entry.model_dump(by_alias=True, mode='json')
        item.update({'camera': _SYSTEM_PARTITION, 'documentType': 'creditLedger'})
        self._container.upsert_item(item)

    def get_wallet(self, configured: bool) -> CreditWallet:
        with self._lock:
            wallet = self._ensure_wallet()
            return CreditWallet(
                balance=int(wallet['balance']),
                initialCredits=int(wallet.get('initialCredits', _INITIAL_CREDITS)),
                configured=configured,
            )

    def charge_lookup(self, vehicle_number: str) -> CreditLedgerEntry | None:
        with self._lock:
            wallet = self._ensure_wallet()
            balance = int(wallet['balance'])
            if balance < 1:
                return None
            balance -= 1
            wallet['balance'] = balance
            self._container.replace_item(item=wallet['id'], body=wallet)
            entry = CreditLedgerEntry(
                amount=-1,
                balanceAfter=balance,
                reason='Vehicle registration lookup',
                vehicleNumber=vehicle_number,
                provider='DataFlag',
            )
            self._save_ledger(entry)
            return entry

    def list_ledger(self) -> list[CreditLedgerEntry]:
        items = list(
            self._container.query_items(
                query=(
                    "SELECT * FROM c WHERE c.documentType = 'creditLedger' "
                    'AND c.camera = @camera'
                ),
                parameters=[{'name': '@camera', 'value': _SYSTEM_PARTITION}],
                partition_key=_SYSTEM_PARTITION,
            )
        )
        entries = [CreditLedgerEntry.model_validate(item) for item in items]
        return sorted(entries, key=lambda entry: entry.created_at, reverse=True)


def create_credit_store() -> CreditStore:
    settings = get_settings()
    if settings.cosmos_endpoint:
        return CosmosCreditStore(settings.cosmos_endpoint, settings.cosmos_database)
    return MemoryCreditStore()


credit_store = create_credit_store()

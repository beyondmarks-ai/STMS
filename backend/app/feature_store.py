from threading import RLock

from .feature_models import SandboxPayment, VipVehicle
from .config import get_settings


class FeatureStore:
    def __init__(self) -> None:
        self._vip: dict[str, VipVehicle] = {}
        self._payments: dict[str, SandboxPayment] = {}
        self._lock = RLock()

    def list_vip(self) -> list[VipVehicle]:
        if self._database_enabled:
            with self._connection() as db:
                rows = db.execute("SELECT data FROM stms_documents WHERE document_type = 'vip_vehicle'").fetchall()
                return [VipVehicle.model_validate(row['data']) for row in rows]
        with self._lock:
            return list(self._vip.values())

    def save_vip(self, item: VipVehicle) -> VipVehicle:
        if self._database_enabled:
            from psycopg.types.json import Jsonb
            with self._connection() as db:
                db.execute(
                    "INSERT INTO stms_documents (document_type, document_id, data) VALUES ('vip_vehicle', %s, %s) ON CONFLICT (document_type, document_id) DO UPDATE SET data = EXCLUDED.data",
                    (item.plate, Jsonb(item.model_dump(by_alias=True, mode='json'))),
                )
            return item
        with self._lock:
            self._vip[item.plate] = item
            return item

    def delete_vip(self, plate: str) -> bool:
        if self._database_enabled:
            with self._connection() as db:
                result = db.execute("DELETE FROM stms_documents WHERE document_type = 'vip_vehicle' AND document_id = %s", (plate,))
                return result.rowcount > 0
        with self._lock:
            return self._vip.pop(plate, None) is not None

    def save_payment(self, item: SandboxPayment) -> SandboxPayment:
        with self._lock:
            self._payments[item.id] = item
            return item

    @property
    def _database_enabled(self) -> bool:
        return bool(get_settings().database_secret_arn)

    @staticmethod
    def _connection():
        from .postgres import connection
        return connection()


feature_store = FeatureStore()

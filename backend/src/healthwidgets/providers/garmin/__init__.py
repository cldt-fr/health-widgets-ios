"""Garmin Connect provider (via python-garminconnect)."""

from __future__ import annotations

import logging
import os
import threading
from dataclasses import dataclass
from datetime import date

from garminconnect import Garmin

from ...config import Settings
from ...db import Connection, Database
from ...schemas import DashboardSnapshot
from ...security import Vault
from ..base import LoginNeedsMfa, LoginSuccess, ProviderAuthError
from . import auth
from .fetch import RawCache, fetch_activity_zones, fetch_raw
from .normalize import build_snapshot, week_activity_ids

logger = logging.getLogger(__name__)

PROVIDER = "garmin"

# python-garminconnect falls back to $GARMINTOKENS when login() gets no tokenstore.
# On a multi-user server that would silently hand one account's tokens to everyone.
if os.environ.pop("GARMINTOKENS", None):
    logger.warning("Ignoring GARMINTOKENS: tokens are stored per user in the database")


@dataclass(slots=True)
class _Session:
    garmin: Garmin
    tokens: str


class GarminProvider:
    """Keeps one live Garmin client per user and turns its data into snapshots."""

    def __init__(self, db: Database, vault: Vault, settings: Settings) -> None:
        self._db = db
        self._vault = vault
        self._settings = settings
        self._cache = RawCache()
        self._sessions: dict[str, _Session] = {}
        self._sessions_lock = threading.Lock()
        self._restore_locks: dict[str, threading.Lock] = {}

    # -- sign-in -------------------------------------------------------------------------

    def begin_login(
        self, email: str, password: str, *, is_cn: bool
    ) -> LoginSuccess | LoginNeedsMfa:
        return auth.start_login(email, password, is_cn=is_cn)

    def finish_mfa(self, state: str, code: str, *, is_cn: bool) -> LoginSuccess:
        return auth.complete_mfa(state, code, is_cn=is_cn)

    def forget(self, user_id: str) -> None:
        with self._sessions_lock:
            self._sessions.pop(user_id, None)
        self._cache.drop_user(user_id)

    # -- data ----------------------------------------------------------------------------

    def today(self, connection: Connection) -> date:
        return self._session(connection).garmin.today()

    def fetch_snapshot(
        self, connection: Connection, day: date, *, force: bool
    ) -> DashboardSnapshot:
        session = self._session(connection)
        try:
            bundle = fetch_raw(
                session.garmin,
                user_id=connection.user_id,
                day=day,
                today=session.garmin.today(),
                cache=self._cache,
                force=force,
                live_ttl=self._settings.snapshot_ttl_seconds,
                max_workers=self._settings.garmin_max_workers,
                call_timeout=self._settings.garmin_call_timeout_seconds,
            )
            zones = fetch_activity_zones(
                session.garmin,
                user_id=connection.user_id,
                activity_ids=week_activity_ids(bundle.data.get("week_activities"), day),
                cache=self._cache,
                max_workers=self._settings.garmin_max_workers,
                call_timeout=self._settings.garmin_call_timeout_seconds,
            )
        except ProviderAuthError:
            self.forget(connection.user_id)
            raise
        finally:
            self._persist_tokens(connection.user_id, session)

        logger.debug(
            "Garmin snapshot for %s: %d network calls", connection.user_id, bundle.network_calls
        )
        return build_snapshot(
            bundle.data,
            day=day,
            unit_system=connection.meta.get("unit_system")
            or getattr(session.garmin, "unit_system", None),
            warnings=bundle.warnings,
            activity_zones=zones,
        )

    # -- sessions ------------------------------------------------------------------------

    def _session(self, connection: Connection) -> _Session:
        user_id = connection.user_id
        with self._sessions_lock:
            session = self._sessions.get(user_id)
            if session is not None:
                return session
            restore_lock = self._restore_locks.setdefault(user_id, threading.Lock())

        with restore_lock:  # one restore per user at a time; others wait and reuse it
            with self._sessions_lock:
                session = self._sessions.get(user_id)
                if session is not None:
                    return session
            if not connection.secret:
                raise ProviderAuthError("No Garmin session stored for this account.")
            secret = self._vault.decrypt(connection.secret)
            garmin = auth.restore_session(secret, is_cn=bool(connection.meta.get("is_cn")))
            session = _Session(garmin=garmin, tokens=secret)
            self._persist_tokens(user_id, session)  # restore may have refreshed them
            with self._sessions_lock:
                self._sessions[user_id] = session
            return session

    def _persist_tokens(self, user_id: str, session: _Session) -> None:
        """Save refreshed tokens: Garmin rotates refresh tokens, losing one logs the user out."""
        try:
            current = session.garmin.client.dumps()
        except Exception:  # pragma: no cover - defensive, dumps() is a plain json.dumps
            logger.exception("Could not serialize Garmin tokens")
            return
        if current != session.tokens:
            self._db.update_connection_secret(user_id, PROVIDER, self._vault.encrypt(current))
            session.tokens = current
            logger.info("Persisted refreshed Garmin tokens for %s", user_id)

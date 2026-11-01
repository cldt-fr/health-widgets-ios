"""Application service: devices, provider connections and snapshot orchestration."""

from __future__ import annotations

import logging
import threading
import time
from datetime import date, timedelta

from .config import Settings
from .db import Connection, Database, utcnow
from .providers.base import (
    LoginNeedsMfa,
    LoginSuccess,
    ProviderAuthError,
    ProviderError,
    ProviderRateLimitedError,
)
from .providers.demo import DemoProvider
from .providers.garmin import GarminProvider
from .schemas import (
    ConnectionInfo,
    ConnectionStatus,
    ConnectResponse,
    ConnectResult,
    DashboardSnapshot,
    GarminConnectRequest,
    MeResponse,
    MfaRequest,
    ProviderId,
    RegisterDeviceResponse,
)
from .security import Vault, constant_time_equals, hash_token, new_device_token

logger = logging.getLogger(__name__)

MFA_CHALLENGE_LIFETIME = timedelta(minutes=10)
MFA_MAX_ATTEMPTS = 5
LOGIN_WINDOW = timedelta(minutes=15)
SNAPSHOT_SAVE_INTERVAL = 60.0  # seconds between two persisted copies of the same day
REVIEW_ACCOUNT_NAME = "Compte de revue (données d'exemple)"


class ServiceError(Exception):
    def __init__(
        self, status: int, code: str, message: str, retry_after_seconds: int | None = None
    ) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retry_after_seconds = retry_after_seconds


class HealthService:
    def __init__(
        self, settings: Settings, db: Database, vault: Vault, signup_code: str | None = None
    ) -> None:
        self.settings = settings
        self.signup_code = signup_code
        self.db = db
        self.vault = vault
        self.garmin = GarminProvider(db, vault, settings)
        self.demo = DemoProvider()
        self._user_locks: dict[str, threading.Lock] = {}
        self._user_locks_guard = threading.Lock()
        self._last_forced: dict[str, float] = {}
        self._last_saved: dict[tuple[str, str], float] = {}

    # -- devices -------------------------------------------------------------------------

    def register_device(self, name: str | None, signup_code: str | None) -> RegisterDeviceResponse:
        expected = self.signup_code
        if expected and not (signup_code and constant_time_equals(signup_code, expected)):
            raise ServiceError(
                403, "invalid_signup_code", "This server requires a valid signup code."
            )
        token = new_device_token()
        user_id = self.db.create_user_with_device(hash_token(token), name)
        logger.info("Registered device %r for new user %s", name, user_id)
        return RegisterDeviceResponse(token=token, user_id=user_id)

    def authenticate(self, token: str) -> str | None:
        return self.db.user_for_token(hash_token(token))

    def delete_account(self, user_id: str) -> None:
        self.garmin.forget(user_id)
        self.db.delete_user(user_id)

    # -- connections ---------------------------------------------------------------------

    def me(self, user_id: str) -> MeResponse:
        return MeResponse(
            user_id=user_id,
            connections=[self._connection_info(c) for c in self.db.list_connections(user_id)],
        )

    def connect_garmin(self, user_id: str, request: GarminConnectRequest) -> ConnectResponse:
        since = utcnow() - LOGIN_WINDOW
        if (
            self.db.count_login_attempts_since(user_id, "garmin", since)
            >= self.settings.max_login_attempts
        ):
            raise ServiceError(
                429,
                "too_many_login_attempts",
                "Too many sign-in attempts. Wait a few minutes: Garmin locks accounts that "
                "fail repeatedly.",
                retry_after_seconds=int(LOGIN_WINDOW.total_seconds()),
            )
        self.db.record_login_attempt(user_id, "garmin")
        if self._is_review_login(request):
            return self._store_review_account(user_id)
        try:
            result = self.garmin.begin_login(request.email, request.password, is_cn=request.is_cn)
        except ProviderError as exc:
            raise _service_error(exc) from exc

        if isinstance(result, LoginNeedsMfa):
            challenge_id = self.db.create_challenge(
                user_id,
                "garmin",
                self.vault.encrypt(result.state),
                result.meta,
                utcnow() + MFA_CHALLENGE_LIFETIME,
            )
            return ConnectResponse(status=ConnectResult.mfa_required, challenge_id=challenge_id)
        return self._store_garmin(user_id, result)

    def submit_garmin_mfa(self, user_id: str, request: MfaRequest) -> ConnectResponse:
        self.db.purge_expired_challenges()
        challenge = self.db.get_challenge(request.challenge_id, user_id)
        if challenge is None or challenge.provider != "garmin":
            raise ServiceError(
                410, "mfa_challenge_expired", "This sign-in expired. Please start again."
            )
        if challenge.attempts >= MFA_MAX_ATTEMPTS:
            self.db.delete_challenge(challenge.id)
            raise ServiceError(429, "too_many_mfa_attempts", "Too many codes tried. Start again.")
        self.db.increment_challenge_attempts(challenge.id)
        try:
            login = self.garmin.finish_mfa(
                self.vault.decrypt(challenge.secret),
                request.code,
                is_cn=bool(challenge.meta.get("is_cn")),
            )
        except ProviderError as exc:
            raise _service_error(exc) from exc
        self.db.delete_challenge(challenge.id)
        return self._store_garmin(user_id, login)

    def connect_demo(self, user_id: str) -> ConnectResponse:
        if not self.settings.enable_demo_provider:
            raise ServiceError(404, "provider_not_available", "The demo provider is disabled.")
        self.db.upsert_connection(
            user_id,
            ProviderId.demo,
            status=ConnectionStatus.connected,
            secret=None,
            external_id="demo",
            display_name="demo",
            full_name="Compte démo",
            meta={"unit_system": "metric"},
        )
        return ConnectResponse(
            status=ConnectResult.connected,
            connection=self._connection_info(self.db.get_connection(user_id, ProviderId.demo)),
        )

    def disconnect(self, user_id: str, provider: ProviderId) -> None:
        if provider == ProviderId.garmin:
            self.garmin.forget(user_id)
        if not self.db.delete_connection(user_id, provider):
            raise ServiceError(404, "not_connected", f"No {provider.value} account is connected.")

    def _store_garmin(self, user_id: str, login: LoginSuccess) -> ConnectResponse:
        self.db.upsert_connection(
            user_id,
            ProviderId.garmin,
            status=ConnectionStatus.connected,
            secret=self.vault.encrypt(login.secret),
            external_id=login.account.external_id,
            display_name=login.account.display_name,
            full_name=login.account.full_name,
            meta=login.account.meta,
        )
        self.garmin.forget(user_id)  # the next fetch restores the brand-new session
        connection = self.db.get_connection(user_id, ProviderId.garmin)
        logger.info("Garmin account connected for user %s", user_id)
        return ConnectResponse(
            status=ConnectResult.connected, connection=self._connection_info(connection)
        )

    def _is_review_login(self, request: GarminConnectRequest) -> bool:
        email, password = self.settings.review_email, self.settings.review_password
        if not (email and password):
            return False
        # Both comparisons always run, in constant time.
        email_ok = constant_time_equals(request.email.strip().lower(), email.strip().lower())
        password_ok = constant_time_equals(request.password, password)
        return email_ok and password_ok

    def _store_review_account(self, user_id: str) -> ConnectResponse:
        """App Review: a Garmin connection served by the demo data (see Settings)."""
        self.db.upsert_connection(
            user_id,
            ProviderId.garmin,
            status=ConnectionStatus.connected,
            secret=None,
            external_id="app-review",
            display_name="app-review",
            full_name=REVIEW_ACCOUNT_NAME,
            meta={"unit_system": "metric", "review": True},
        )
        self.garmin.forget(user_id)  # drop the session of a previous real account, if any
        logger.info("App Review account connected for user %s", user_id)
        connection = self.db.get_connection(user_id, ProviderId.garmin)
        return ConnectResponse(
            status=ConnectResult.connected, connection=self._connection_info(connection)
        )

    @staticmethod
    def _connection_info(connection: Connection | None) -> ConnectionInfo:
        assert connection is not None
        return ConnectionInfo(
            provider=ProviderId(connection.provider),
            status=ConnectionStatus(connection.status),
            display_name=connection.display_name,
            full_name=connection.full_name,
            connected_at=connection.created_at,
            last_success_at=connection.last_success_at,
            last_error=connection.last_error,
        )

    # -- snapshots -----------------------------------------------------------------------

    def snapshot(self, user_id: str, day: date | None, *, force: bool) -> DashboardSnapshot:
        connection = self._active_connection(user_id)
        provider = connection.provider

        if provider == ProviderId.demo:
            return self.demo.fetch_snapshot(day or date.today(), force=force)
        if connection.meta.get("review"):
            # App Review account: sample data, Garmin is never called.
            self.db.mark_connection_success(user_id, provider)
            return self.demo.fetch_snapshot(day or date.today(), force=force)

        if connection.status == ConnectionStatus.reauth_required:
            return self._fallback(user_id, day, ProviderAuthError("Garmin session expired"))

        with self._user_lock(user_id):  # one Garmin fetch per user at a time
            now = time.monotonic()
            if force:
                # No entry means "never": monotonic time starts near 0 right after a boot.
                last = self._last_forced.get(user_id)
                if last is not None and now - last < self.settings.min_force_refresh_seconds:
                    force = False  # refreshed a few seconds ago: cached data is fresh
                else:
                    self._last_forced[user_id] = now
            try:
                day = day or self.garmin.today(connection)
                snapshot = self.garmin.fetch_snapshot(connection, day, force=force)
            except ProviderAuthError as exc:
                self.db.mark_connection_error(
                    user_id, provider, str(exc), status=ConnectionStatus.reauth_required
                )
                return self._fallback(user_id, day, exc)
            except ProviderError as exc:
                self.db.mark_connection_error(user_id, provider, str(exc))
                return self._fallback(user_id, day, exc)

        self.db.mark_connection_success(user_id, provider)
        self._save(user_id, snapshot)
        return snapshot

    def _active_connection(self, user_id: str) -> Connection:
        connections = {c.provider: c for c in self.db.list_connections(user_id)}
        for provider in (ProviderId.garmin, ProviderId.demo):
            if provider in connections:
                return connections[provider]
        raise ServiceError(409, "no_provider_connected", "Connect a watch provider first.")

    def _fallback(self, user_id: str, day: date | None, exc: ProviderError) -> DashboardSnapshot:
        """Serve the last good snapshot (flagged) instead of failing the widget."""
        stored = self.db.get_snapshot(user_id, day.isoformat()) if day else None
        # A new day may have started since the last good fetch: older data beats an
        # empty widget, and the payload carries its own calendarDate.
        stored = stored or self.db.get_latest_snapshot(user_id)
        if stored is None:
            raise _service_error(exc)
        snapshot = DashboardSnapshot.model_validate_json(self.vault.decrypt(stored[0]))
        update: dict[str, object] = {"stale": True}
        if isinstance(exc, ProviderAuthError):
            update["needs_reauth"] = True
        return snapshot.model_copy(update=update)

    def _save(self, user_id: str, snapshot: DashboardSnapshot) -> None:
        key = (user_id, snapshot.calendar_date)
        now = time.monotonic()
        last = self._last_saved.get(key)
        if last is not None and now - last < SNAPSHOT_SAVE_INTERVAL:
            return
        self._last_saved[key] = now
        payload = self.vault.encrypt(snapshot.model_dump_json(by_alias=True))
        self.db.save_snapshot(user_id, snapshot.calendar_date, payload)

    def _user_lock(self, user_id: str) -> threading.Lock:
        with self._user_locks_guard:
            return self._user_locks.setdefault(user_id, threading.Lock())


def _service_error(exc: ProviderError) -> ServiceError:
    status = {
        "provider_reauth_required": 401,
        "invalid_credentials": 401,
        "invalid_mfa_code": 400,
        "provider_rate_limited": 429,
        "provider_unavailable": 502,
    }.get(exc.code, 502)
    retry = exc.retry_after_seconds if isinstance(exc, ProviderRateLimitedError) else None
    return ServiceError(status, exc.code, str(exc), retry_after_seconds=retry)

from __future__ import annotations

import json
from collections import Counter
from datetime import date, timedelta
from typing import Any

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from garminconnect import GarminConnectAuthenticationError

from healthwidgets.config import Settings
from healthwidgets.db import utcnow
from healthwidgets.main import create_app
from healthwidgets.providers.base import (
    Account,
    InvalidMfaCodeError,
    LoginNeedsMfa,
    LoginSuccess,
)
from healthwidgets.providers.garmin import auth

from . import garmin_payloads as raw

TOKENS = json.dumps({"di_token": "access-1", "di_refresh_token": "refresh-1", "di_client_id": "c"})


class FakeClient:
    def __init__(self, tokens: str) -> None:
        self.tokens = tokens

    def dumps(self) -> str:
        return self.tokens


class FakeGarmin:
    """Stands in for ``garminconnect.Garmin``: serves recorded payloads, counts calls."""

    def __init__(self, tokens: str = TOKENS) -> None:
        self.client = FakeClient(tokens)
        self.calls: Counter[str] = Counter()
        self.unit_system = "metric"
        self.fail_with: Exception | None = None

    def today(self) -> date:
        return date(2026, 1, 14)

    def _serve(self, name: str, value: Any) -> Any:
        self.calls[name] += 1
        if self.fail_with is not None:
            raise self.fail_with
        return value

    def get_user_summary(self, d: str) -> Any:
        return self._serve("summary", raw.summary())

    def get_heart_rates(self, d: str) -> Any:
        return self._serve("heart_rates", raw.heart_rates())

    def get_stress_data(self, d: str) -> Any:
        return self._serve("stress", raw.stress())

    def get_weekly_intensity_minutes(self, start: str, end: str) -> Any:
        return self._serve("intensity_week", raw.intensity_week())

    def get_activities(self, start: int, limit: int) -> Any:
        return self._serve("activities", raw.activities())

    def get_sleep_data(self, d: str) -> Any:
        return self._serve("sleep", raw.sleep())

    def get_hrv_data(self, d: str) -> Any:
        return self._serve("hrv", raw.hrv())

    def get_training_readiness(self, d: str) -> Any:
        return self._serve("readiness", raw.readiness())

    def get_training_status(self, d: str) -> Any:
        return self._serve("training_status", raw.training_status())

    def get_daily_steps(self, start: str, end: str) -> Any:
        return self._serve("steps_history", raw.daily_steps())

    def get_sleep_daily(self, start: str, end: str) -> Any:
        return self._serve("sleep_history", raw.sleep_history())

    def get_hrv_data_range(self, start: str, end: str) -> Any:
        return self._serve("hrv_history", None)

    def get_rhr_daily(self, start: str, end: str) -> Any:
        return self._serve("rhr_history", raw.rhr_history())

    def get_device_last_used(self) -> Any:
        return self._serve("device", raw.device())

    def get_race_predictions(self) -> Any:
        return self._serve("race_predictions", raw.race_predictions())

    def get_activities_by_date(self, start: str, end: str) -> Any:
        return self._serve("week_activities", raw.week_activities())

    def query_garmin_graphql(self, query: dict[str, Any]) -> Any:
        if "trainingPlanScalar" in query["query"]:
            return self._serve("training_plan", raw.training_plan())
        return self._serve("schedule", raw.schedule())

    def get_activity_hr_in_timezones(self, activity_id: int) -> Any:
        self.calls["zones"] += 1
        return raw.hr_zones().get(activity_id, [])


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(
        data_dir=tmp_path,
        encryption_key=Fernet.generate_key().decode(),
        enable_demo_provider=True,
        min_force_refresh_seconds=60,
        open_registration=True,
    )


@pytest.fixture
def client(settings: Settings) -> TestClient:
    return TestClient(create_app(settings))


@pytest.fixture
def garmin(monkeypatch: pytest.MonkeyPatch) -> FakeGarmin:
    fake = FakeGarmin()
    monkeypatch.setattr(auth, "restore_session", lambda secret, is_cn=False: fake)
    monkeypatch.setattr(
        auth,
        "start_login",
        lambda email, password, is_cn=False: LoginNeedsMfa(
            state='{"flow": "ios"}', meta={"is_cn": is_cn}
        ),
    )

    def complete(state: str, code: str, is_cn: bool = False) -> LoginSuccess:
        if code != "123456":
            raise InvalidMfaCodeError("This verification code was not accepted.")
        return LoginSuccess(
            account=Account(
                external_id="42",
                display_name="runner",
                full_name="Runner",
                meta={"is_cn": False, "unit_system": "metric"},
            ),
            secret=TOKENS,
        )

    monkeypatch.setattr(auth, "complete_mfa", complete)
    return fake


def register(client: TestClient) -> dict[str, str]:
    response = client.post("/v1/devices", json={"name": "iPhone"})
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['token']}"}


def connect_garmin(client: TestClient, headers: dict[str, str]) -> None:
    started = client.post(
        "/v1/connections/garmin",
        json={"email": "me@example.com", "password": "pw"},
        headers=headers,
    )
    assert started.status_code == 200, started.text
    challenge = started.json()["challengeId"]
    done = client.post(
        "/v1/connections/garmin/mfa",
        json={"challengeId": challenge, "code": "123456"},
        headers=headers,
    )
    assert done.status_code == 200, done.text


def test_health(client: TestClient) -> None:
    assert client.get("/health").json()["status"] == "ok"


def test_requires_a_device_token(client: TestClient) -> None:
    response = client.get("/v1/me")
    assert response.status_code == 401
    assert response.json() == {
        "error": {"code": "invalid_token", "message": "Unknown or revoked device token."}
    }
    assert client.get("/v1/me", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_signup_code(settings: Settings) -> None:
    settings.signup_code = "s3cret"
    settings.open_registration = False
    client = TestClient(create_app(settings))
    assert client.post("/v1/devices", json={}).status_code == 403
    assert client.post("/v1/devices", json={"signupCode": "wrong"}).status_code == 403
    assert client.post("/v1/devices", json={"signupCode": "s3cret"}).status_code == 201


def test_signup_code_is_generated_when_not_configured(settings: Settings) -> None:
    settings.open_registration = False
    client = TestClient(create_app(settings))
    code = (settings.data_dir / "signup-code").read_text().strip()
    assert len(code) == 14 and code.count("-") == 2
    assert client.post("/v1/devices", json={}).status_code == 403
    assert client.post("/v1/devices", json={"signupCode": code}).status_code == 201
    # Stable across restarts.
    TestClient(create_app(settings))
    assert (settings.data_dir / "signup-code").read_text().strip() == code


def test_snapshot_needs_a_connection(client: TestClient) -> None:
    headers = register(client)
    response = client.get("/v1/snapshot", headers=headers)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "no_provider_connected"


def test_garmin_mfa_flow(client: TestClient, garmin: FakeGarmin) -> None:
    headers = register(client)
    started = client.post(
        "/v1/connections/garmin",
        json={"email": "me@example.com", "password": "pw"},
        headers=headers,
    ).json()
    assert started["status"] == "mfa_required" and started["challengeId"]

    wrong = client.post(
        "/v1/connections/garmin/mfa",
        json={"challengeId": started["challengeId"], "code": "000000"},
        headers=headers,
    )
    assert wrong.status_code == 400
    assert wrong.json()["error"]["code"] == "invalid_mfa_code"

    done = client.post(
        "/v1/connections/garmin/mfa",
        json={"challengeId": started["challengeId"], "code": "123456"},
        headers=headers,
    ).json()
    assert done["status"] == "connected"
    assert done["connection"]["provider"] == "garmin"
    assert done["connection"]["displayName"] == "runner"

    # The challenge is single use.
    again = client.post(
        "/v1/connections/garmin/mfa",
        json={"challengeId": started["challengeId"], "code": "123456"},
        headers=headers,
    )
    assert again.status_code == 410

    me = client.get("/v1/me", headers=headers).json()
    assert [c["provider"] for c in me["connections"]] == ["garmin"]
    assert me["connections"][0]["status"] == "connected"


def test_snapshot_caching_and_token_rotation(client: TestClient, garmin: FakeGarmin) -> None:
    headers = register(client)
    connect_garmin(client, headers)

    response = client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["steps"]["count"] == 9312
    assert body["sleep"]["score"] == 84
    assert body["source"]["provider"] == "garmin"
    assert body["stale"] is False
    assert body["trainingWeek"]["count"] == 3
    assert body["upcomingWorkouts"][0]["name"] == "Tempo 3x10"
    first_calls = sum(garmin.calls.values())
    # One call per endpoint (18), plus heart-rate zones for this week's 3 activities.
    assert first_calls == 18 + 3
    assert garmin.calls["zones"] == 3

    # Everything is fresh: no Garmin call at all.
    client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers)
    assert sum(garmin.calls.values()) == first_calls

    # A forced refresh only refetches live metrics (steps, HR, stress, activities...).
    garmin.client.tokens = TOKENS.replace("access-1", "access-2")  # library refreshed tokens
    client.get("/v1/snapshot", params={"date": "2026-01-14", "refresh": "true"}, headers=headers)
    assert garmin.calls["summary"] == 2 and garmin.calls["sleep"] == 1

    # ...and the rotated tokens were persisted, encrypted.
    service = client.app.state.service
    user_id = service.authenticate(headers["Authorization"].split()[1])
    stored = service.db.get_connection(user_id, "garmin")
    assert b"access-2" not in stored.secret
    assert "access-2" in service.vault.decrypt(stored.secret)

    # A second forced refresh right away is throttled.
    client.get("/v1/snapshot", params={"date": "2026-01-14", "refresh": "true"}, headers=headers)
    assert garmin.calls["summary"] == 2


def test_expired_session_serves_stale_data(client: TestClient, garmin: FakeGarmin) -> None:
    headers = register(client)
    connect_garmin(client, headers)
    assert (
        client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers).status_code
        == 200
    )

    garmin.fail_with = GarminConnectAuthenticationError("refresh token revoked")
    service = client.app.state.service
    service._last_forced.clear()
    response = client.get(
        "/v1/snapshot", params={"date": "2026-01-14", "refresh": "true"}, headers=headers
    )
    assert response.status_code == 200
    assert response.json()["stale"] is True
    assert response.json()["needsReauth"] is True
    assert response.json()["steps"]["count"] == 9312

    me = client.get("/v1/me", headers=headers).json()
    assert me["connections"][0]["status"] == "reauth_required"


def test_throttles_work_right_after_boot(
    client: TestClient, garmin: FakeGarmin, monkeypatch: pytest.MonkeyPatch
) -> None:
    """time.monotonic() counts from boot: it is close to 0 on a fresh CI runner or server."""
    import types

    import healthwidgets.service as service_module

    # The service's clock only: freezing time.monotonic globally would stall threads.
    monkeypatch.setattr(service_module, "time", types.SimpleNamespace(monotonic=lambda: 5.0))
    headers = register(client)
    connect_garmin(client, headers)
    client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers)
    # The first snapshot is persisted for the stale fallback...
    service = client.app.state.service
    user_id = service.authenticate(headers["Authorization"].split()[1])
    assert service.db.get_snapshot(user_id, "2026-01-14") is not None
    # ...and the first forced refresh is honoured.
    client.get("/v1/snapshot", params={"date": "2026-01-14", "refresh": "true"}, headers=headers)
    assert garmin.calls["summary"] == 2


def test_expired_session_without_cache_is_an_error(client: TestClient, garmin: FakeGarmin) -> None:
    headers = register(client)
    connect_garmin(client, headers)
    garmin.fail_with = GarminConnectAuthenticationError("revoked")
    response = client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "provider_reauth_required"


def test_demo_provider(client: TestClient) -> None:
    headers = register(client)
    assert client.post("/v1/connections/demo", headers=headers).json()["status"] == "connected"
    body = client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers).json()
    assert body["source"]["provider"] == "demo"
    assert body["sleep"]["stages"]
    assert body["heartRate"]["series"]
    assert body["calendarDate"] == "2026-01-14"


def test_disconnect_and_delete_account(client: TestClient, garmin: FakeGarmin) -> None:
    headers = register(client)
    connect_garmin(client, headers)
    assert client.delete("/v1/connections/garmin", headers=headers).status_code == 204
    assert client.delete("/v1/connections/garmin", headers=headers).status_code == 404
    assert client.get("/v1/me", headers=headers).json()["connections"] == []

    assert client.delete("/v1/me", headers=headers).status_code == 204
    assert client.get("/v1/me", headers=headers).status_code == 401


def test_login_attempts_are_limited(client: TestClient, garmin: FakeGarmin) -> None:
    headers = register(client)
    for _ in range(5):
        client.post(
            "/v1/connections/garmin",
            json={"email": "me@example.com", "password": "pw"},
            headers=headers,
        )
    blocked = client.post(
        "/v1/connections/garmin",
        json={"email": "me@example.com", "password": "pw"},
        headers=headers,
    )
    assert blocked.status_code == 429
    assert blocked.headers["Retry-After"] == "900"


REVIEW = {"email": "Review@Example.com", "password": "Revue-abcd-2345"}


def test_review_account_uses_sample_data_without_garmin(
    settings: Settings, garmin: FakeGarmin
) -> None:
    settings.review_email, settings.review_password = REVIEW["email"], REVIEW["password"]
    client = TestClient(create_app(settings))
    headers = register(client)
    signed_in = client.post(
        "/v1/connections/garmin",
        json={"email": " review@example.com ", "password": REVIEW["password"]},
        headers=headers,
    )
    assert signed_in.status_code == 200, signed_in.text
    assert signed_in.json()["status"] == "connected"  # no verification code asked
    [connection] = client.get("/v1/me", headers=headers).json()["connections"]
    assert connection["provider"] == "garmin"
    assert connection["fullName"] == "Compte de revue (données d'exemple)"

    snapshot = client.get("/v1/snapshot", headers=headers)
    assert snapshot.status_code == 200, snapshot.text
    assert snapshot.json()["source"]["provider"] == "demo"  # the app labels it as demo data
    assert not garmin.calls  # Garmin is never called

    # Disconnecting works like for a real account.
    assert client.delete("/v1/connections/garmin", headers=headers).status_code == 204
    assert client.get("/v1/snapshot", headers=headers).status_code == 409


def test_review_account_needs_the_exact_password(settings: Settings, garmin: FakeGarmin) -> None:
    settings.review_email, settings.review_password = REVIEW["email"], REVIEW["password"]
    client = TestClient(create_app(settings))
    headers = register(client)
    response = client.post(
        "/v1/connections/garmin",
        json={"email": REVIEW["email"], "password": "revue-abcd-2345"},
        headers=headers,
    )
    # Not the review password: this is a regular Garmin sign-in (which asks for a code).
    assert response.json()["status"] == "mfa_required"


def test_review_account_is_off_without_a_password(settings: Settings, garmin: FakeGarmin) -> None:
    settings.review_email = REVIEW["email"]
    client = TestClient(create_app(settings))
    response = client.post(
        "/v1/connections/garmin",
        json={"email": REVIEW["email"], "password": "anything"},
        headers=register(client),
    )
    assert response.json()["status"] == "mfa_required"


def test_privacy_policy_names_the_operator(settings: Settings) -> None:
    settings.privacy_operator = "Jane <Doe>"
    settings.privacy_contact = "jane@example.com"
    settings.privacy_hosting = "Example Cloud, en France"
    page = TestClient(create_app(settings)).get("/privacy")
    assert page.status_code == 200
    assert page.headers["content-type"].startswith("text/html")
    assert "Jane &lt;Doe&gt;" in page.text  # escaped
    assert 'href="mailto:jane@example.com"' in page.text
    assert "Example Cloud, en France" in page.text


def test_privacy_policy_works_without_settings(client: TestClient) -> None:
    page = client.get("/privacy")
    assert page.status_code == 200
    assert "la personne qui l'a installé" in page.text
    assert "$" not in page.text  # every placeholder was filled


def test_old_sign_in_attempts_are_purged(client: TestClient) -> None:
    service = client.app.state.service
    headers = register(client)
    user_id = service.authenticate(headers["Authorization"].split()[1])
    service.db.record_login_attempt(user_id, "garmin")
    month_ago = utcnow() - timedelta(days=30)
    service.db.purge_login_attempts(utcnow() - timedelta(days=1))
    assert service.db.count_login_attempts_since(user_id, "garmin", month_ago) == 1
    service.db.purge_login_attempts(utcnow() + timedelta(seconds=1))
    assert service.db.count_login_attempts_since(user_id, "garmin", month_ago) == 0


def test_cleanup_runs_at_most_hourly(
    client: TestClient, garmin: FakeGarmin, monkeypatch: pytest.MonkeyPatch
) -> None:
    service = client.app.state.service
    purges: list[object] = []
    monkeypatch.setattr(service.db, "purge_login_attempts", purges.append)
    headers = register(client)
    connect_garmin(client, headers)
    for _ in range(2):
        client.get("/v1/snapshot", params={"date": "2026-01-14"}, headers=headers)
    assert len(purges) == 1

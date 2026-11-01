"""Parallel, cache-aware retrieval of the raw Garmin endpoints behind a snapshot.

Each endpoint has its own freshness budget: steps or body battery move every few
minutes, sleep and HRV once a night, race predictions barely at all. Respecting that
keeps the number of Garmin calls low (the account is shared with the official app and
Garmin rate-limits aggressively) while widgets still get fresh numbers.
"""

from __future__ import annotations

import logging
import threading
import time
from collections import OrderedDict
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

from garminconnect import Garmin, GarminConnectNotFoundError

from ..base import ProviderAuthError, ProviderRateLimitedError
from .auth import describe, is_auth_error, is_rate_limit_error

logger = logging.getLogger(__name__)

MINUTE = 60
HOUR = 60 * MINUTE


@dataclass(frozen=True, slots=True)
class EndpointSpec:
    name: str
    call: Callable[[Garmin], Any]
    ttl: float
    # Refetched when the user explicitly asks for a refresh.
    live: bool = False
    # Shorter TTL while the payload is still empty (e.g. sleep before the morning sync).
    empty_ttl: float | None = None
    is_empty: Callable[[Any], bool] | None = None
    # False for endpoints that don't depend on the requested day (latest activities...).
    per_day: bool = True


def _empty(value: Any) -> bool:
    return value is None or value == {} or value == []


def _sleep_missing(value: Any) -> bool:
    dto = (value or {}).get("dailySleepDTO") if isinstance(value, dict) else None
    return not (isinstance(dto, dict) and dto.get("sleepTimeSeconds"))


def _hrv_missing(value: Any) -> bool:
    return not (isinstance(value, dict) and value.get("hrvSummary"))


def endpoint_specs(day: date, today: date, live_ttl: float = 5 * MINUTE) -> list[EndpointSpec]:
    d = day.isoformat()
    week_start = (day - timedelta(days=6)).isoformat()
    monday = (day - timedelta(days=day.weekday())).isoformat()
    previous_monday = (day - timedelta(days=day.weekday() + 7)).isoformat()
    in_a_week = (day + timedelta(days=6)).isoformat()
    schedule_query = {
        "query": f'query{{workoutScheduleSummariesScalar(startDate:"{d}", endDate:"{in_a_week}")}}'
    }
    plan_query = {
        "query": (
            f'query{{trainingPlanScalar(calendarDate:"{d}", lang:"en-US", '
            'firstDayOfWeek:"monday")}'
        )
    }
    past = day < today

    def ttl(value: float) -> float:
        # Past days only change if the watch syncs late: cache them for long.
        return 6 * HOUR if past else value

    live = live_ttl

    return [
        EndpointSpec("summary", lambda g: g.get_user_summary(d), ttl(live), live=True),
        EndpointSpec("heart_rates", lambda g: g.get_heart_rates(d), ttl(live), live=True),
        EndpointSpec("stress", lambda g: g.get_stress_data(d), ttl(live), live=True),
        # Body Battery has no endpoint of its own here: its intraday series ships with
        # the stress payload and its daily values with the summary.
        EndpointSpec(
            "intensity_week",
            lambda g: g.get_weekly_intensity_minutes(monday, d),
            ttl(15 * MINUTE),
            live=True,
        ),
        EndpointSpec(
            "activities", lambda g: g.get_activities(0, 5), live, live=True, per_day=False
        ),
        EndpointSpec(
            "sleep",
            lambda g: g.get_sleep_data(d),
            ttl(1 * HOUR),
            empty_ttl=10 * MINUTE,
            is_empty=_sleep_missing,
        ),
        EndpointSpec(
            "hrv",
            lambda g: g.get_hrv_data(d),
            ttl(1 * HOUR),
            empty_ttl=15 * MINUTE,
            is_empty=_hrv_missing,
        ),
        EndpointSpec(
            "readiness",
            lambda g: g.get_training_readiness(d),
            ttl(20 * MINUTE),
            empty_ttl=10 * MINUTE,
        ),
        EndpointSpec("training_status", lambda g: g.get_training_status(d), ttl(30 * MINUTE)),
        EndpointSpec("steps_history", lambda g: g.get_daily_steps(week_start, d), ttl(1 * HOUR)),
        EndpointSpec("sleep_history", lambda g: g.get_sleep_daily(week_start, d), ttl(2 * HOUR)),
        EndpointSpec("hrv_history", lambda g: g.get_hrv_data_range(week_start, d), ttl(2 * HOUR)),
        EndpointSpec("rhr_history", lambda g: g.get_rhr_daily(week_start, d), ttl(2 * HOUR)),
        EndpointSpec("device", lambda g: g.get_device_last_used(), 1 * HOUR, per_day=False),
        EndpointSpec(
            "race_predictions", lambda g: g.get_race_predictions(), 6 * HOUR, per_day=False
        ),
        # This week and last week, for the training-week widget.
        EndpointSpec(
            "week_activities",
            lambda g: g.get_activities_by_date(previous_monday, d),
            ttl(live),
            live=True,
        ),
        # Planned workouts (calendar) and Garmin Coach plans, through Garmin's GraphQL API.
        EndpointSpec(
            "schedule", lambda g: g.query_garmin_graphql(schedule_query), ttl(30 * MINUTE)
        ),
        EndpointSpec(
            "training_plan", lambda g: g.query_garmin_graphql(plan_query), ttl(30 * MINUTE)
        ),
    ]


@dataclass(slots=True)
class _Entry:
    value: Any
    fetched_at: float
    ttl: float

    def fresh(self, now: float) -> bool:
        return now - self.fetched_at < self.ttl


class RawCache:
    """Small thread-safe LRU of raw endpoint payloads, keyed per user and endpoint."""

    def __init__(self, max_entries: int = 5000) -> None:
        self._data: OrderedDict[tuple[str, str], _Entry] = OrderedDict()
        self._lock = threading.Lock()
        self._max = max_entries

    def get(self, user_id: str, key: str) -> _Entry | None:
        with self._lock:
            entry = self._data.get((user_id, key))
            if entry is not None:
                self._data.move_to_end((user_id, key))
            return entry

    def put(self, user_id: str, key: str, value: Any, ttl: float) -> None:
        with self._lock:
            self._data[(user_id, key)] = _Entry(value=value, fetched_at=time.monotonic(), ttl=ttl)
            self._data.move_to_end((user_id, key))
            while len(self._data) > self._max:
                self._data.popitem(last=False)

    def drop_user(self, user_id: str) -> None:
        with self._lock:
            for key in [k for k in self._data if k[0] == user_id]:
                del self._data[key]


@dataclass(slots=True)
class RawBundle:
    data: dict[str, Any] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)
    network_calls: int = 0


def fetch_raw(
    garmin: Garmin,
    *,
    user_id: str,
    day: date,
    today: date,
    cache: RawCache,
    force: bool,
    live_ttl: float,
    max_workers: int,
    call_timeout: float,
) -> RawBundle:
    """Return every endpoint payload for ``day``, calling Garmin only for stale entries."""
    bundle = RawBundle()
    now = time.monotonic()
    pending: dict[str, EndpointSpec] = {}
    stale: dict[str, Any] = {}

    for spec in endpoint_specs(day, today, live_ttl):
        key = f"{spec.name}:{day.isoformat()}" if spec.per_day else spec.name
        entry = cache.get(user_id, key)
        if entry is not None:
            stale[spec.name] = entry.value
            if entry.fresh(now) and not (force and spec.live):
                bundle.data[spec.name] = entry.value
                continue
        pending[key] = spec

    if not pending:
        return bundle

    auth_error: BaseException | None = None
    rate_limited = False
    pool = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="garmin")
    try:
        futures = {pool.submit(spec.call, garmin): (key, spec) for key, spec in pending.items()}
        done, not_done = wait(futures, timeout=call_timeout)
        for future in not_done:
            key, spec = futures[future]
            future.cancel()
            bundle.warnings.append(f"{spec.name}: timeout")
            if spec.name in stale:
                bundle.data[spec.name] = stale[spec.name]
        for future in done:
            key, spec = futures[future]
            bundle.network_calls += 1
            try:
                value = future.result()
            except GarminConnectNotFoundError:
                value = None  # No data recorded for that day: a valid, empty answer.
            except Exception as exc:
                if is_auth_error(exc):
                    auth_error = exc
                elif is_rate_limit_error(exc):
                    rate_limited = True
                logger.info("Garmin endpoint %s failed: %s", spec.name, describe(exc))
                bundle.warnings.append(f"{spec.name}: unavailable")
                if spec.name in stale:
                    bundle.data[spec.name] = stale[spec.name]
                continue
            empty = spec.is_empty(value) if spec.is_empty else _empty(value)
            ttl = spec.empty_ttl if (empty and spec.empty_ttl is not None) else spec.ttl
            cache.put(user_id, key, value, ttl)
            bundle.data[spec.name] = value
    finally:
        pool.shutdown(wait=False, cancel_futures=True)

    if auth_error is not None:
        raise ProviderAuthError("The Garmin session is no longer valid.") from auth_error
    if rate_limited and not bundle.data:
        raise ProviderRateLimitedError("Garmin is rate limiting this account right now.")
    return bundle


def fetch_activity_zones(
    garmin: Garmin,
    *,
    user_id: str,
    activity_ids: list[int],
    cache: RawCache,
    max_workers: int,
    call_timeout: float,
) -> dict[int, Any]:
    """Time in heart-rate zones per activity. A finished activity never changes: cache long."""
    zones: dict[int, Any] = {}
    missing = []
    for activity_id in activity_ids[:21]:
        entry = cache.get(user_id, f"zones:{activity_id}")
        if entry is not None:
            zones[activity_id] = entry.value
        else:
            missing.append(activity_id)
    if not missing:
        return zones

    pool = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="garmin-zones")
    try:
        futures = {pool.submit(garmin.get_activity_hr_in_timezones, aid): aid for aid in missing}
        done, _ = wait(futures, timeout=call_timeout)
        for future in done:
            activity_id = futures[future]
            try:
                value = future.result()
            except Exception as exc:  # no HR data, deleted activity...: skip this one
                if is_auth_error(exc):
                    raise ProviderAuthError("The Garmin session is no longer valid.") from exc
                logger.info("HR zones for activity %s unavailable: %s", activity_id, describe(exc))
                continue
            cache.put(user_id, f"zones:{activity_id}", value, 30 * 24 * HOUR)
            zones[activity_id] = value
    finally:
        pool.shutdown(wait=False, cancel_futures=True)
    return zones

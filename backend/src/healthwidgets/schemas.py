"""Public API contract.

Everything a provider returns is normalized into these provider-agnostic models, so the
iOS app and its widgets never deal with Garmin (or Polar, Coros...) payloads directly.
JSON keys are camelCase, timestamps are UTC ISO-8601 without fractional seconds, and
time series use epoch seconds to stay compact for widgets.

Bump ``SCHEMA_VERSION`` on breaking changes (the app checks it).
"""

from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, PlainSerializer
from pydantic.alias_generators import to_camel

SCHEMA_VERSION = 1


def _format_utc(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


UtcDatetime = Annotated[datetime, PlainSerializer(_format_utc, return_type=str)]


class ApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        extra="ignore",
        ser_json_inf_nan="null",
    )


# --------------------------------------------------------------------------- errors


class ErrorBody(ApiModel):
    code: str
    message: str
    retry_after_seconds: int | None = None


class ErrorResponse(ApiModel):
    error: ErrorBody


# ------------------------------------------------------------------ devices & accounts


class RegisterDeviceRequest(ApiModel):
    name: str | None = Field(default=None, max_length=100)
    signup_code: str | None = None


class RegisterDeviceResponse(ApiModel):
    token: str
    user_id: str


class ProviderId(StrEnum):
    garmin = "garmin"
    demo = "demo"


class ConnectionStatus(StrEnum):
    connected = "connected"
    reauth_required = "reauth_required"


class ConnectionInfo(ApiModel):
    provider: ProviderId
    status: ConnectionStatus
    display_name: str | None = None
    full_name: str | None = None
    connected_at: UtcDatetime
    last_success_at: UtcDatetime | None = None
    last_error: str | None = None


class MeResponse(ApiModel):
    user_id: str
    connections: list[ConnectionInfo]


class GarminConnectRequest(ApiModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=512)
    # Accounts registered on garmin.cn live on a separate Garmin backend.
    is_cn: bool = False


class MfaRequest(ApiModel):
    challenge_id: str
    code: str = Field(min_length=4, max_length=12)


class ConnectResult(StrEnum):
    connected = "connected"
    mfa_required = "mfa_required"


class ConnectResponse(ApiModel):
    status: ConnectResult
    challenge_id: str | None = None
    connection: ConnectionInfo | None = None


# --------------------------------------------------------------------------- snapshot


class Point(ApiModel):
    """A time-series sample: ``t`` in epoch seconds (UTC), ``v`` the value."""

    t: int
    v: float


class DailyValue(ApiModel):
    date: str  # YYYY-MM-DD, local calendar date
    value: float | None = None
    goal: float | None = None


class Source(ApiModel):
    provider: ProviderId
    device_name: str | None = None
    device_image_url: str | None = None
    last_sync_at: UtcDatetime | None = None


class StepsMetric(ApiModel):
    count: int
    goal: int | None = None
    distance_meters: float | None = None
    history: list[DailyValue] = []


class CaloriesMetric(ApiModel):
    total: int | None = None
    active: int | None = None
    resting: int | None = None
    goal: int | None = None


class FloorsMetric(ApiModel):
    ascended: float | None = None
    goal: float | None = None


class HeartRateMetric(ApiModel):
    resting: int | None = None
    min: int | None = None
    max: int | None = None
    resting_seven_day_avg: int | None = None
    latest: int | None = None
    series: list[Point] = []
    history: list[DailyValue] = []  # resting heart rate, last 7 days


class BodyBatteryMetric(ApiModel):
    current: int | None = None
    highest: int | None = None
    lowest: int | None = None
    charged: int | None = None
    drained: int | None = None
    at_wake: int | None = None
    series: list[Point] = []


class StressMetric(ApiModel):
    average: int | None = None
    max: int | None = None
    current: int | None = None
    qualifier: str | None = None  # calm / balanced / stressful / very_stressful
    rest_seconds: int | None = None
    low_seconds: int | None = None
    medium_seconds: int | None = None
    high_seconds: int | None = None
    series: list[Point] = []


class SleepStage(StrEnum):
    deep = "deep"
    light = "light"
    rem = "rem"
    awake = "awake"


class SleepSegment(ApiModel):
    start: int  # epoch seconds
    end: int
    stage: SleepStage


class SleepMetric(ApiModel):
    calendar_date: str
    score: int | None = None
    quality: str | None = None  # excellent / good / fair / poor
    duration_seconds: int | None = None
    deep_seconds: int | None = None
    light_seconds: int | None = None
    rem_seconds: int | None = None
    awake_seconds: int | None = None
    nap_seconds: int | None = None
    start: UtcDatetime | None = None
    end: UtcDatetime | None = None
    need_seconds: int | None = None
    avg_overnight_hrv: float | None = None
    resting_heart_rate: int | None = None
    avg_respiration: float | None = None
    avg_spo2: float | None = None
    avg_stress: float | None = None
    body_battery_change: int | None = None
    feedback: str | None = None
    stages: list[SleepSegment] = []
    history: list[DailyValue] = []  # sleep score, last 7 nights


class HrvBaseline(ApiModel):
    low_upper: int | None = None
    balanced_low: int | None = None
    balanced_upper: int | None = None


class HrvMetric(ApiModel):
    last_night_avg: int | None = None
    last_night_high: int | None = None
    weekly_avg: int | None = None
    status: str | None = None  # balanced / unbalanced / low / poor / none
    feedback: str | None = None
    baseline: HrvBaseline | None = None
    readings: list[Point] = []
    history: list[DailyValue] = []  # last-night average, last 7 nights


class ReadinessFactor(ApiModel):
    key: str  # sleep / recovery_time / hrv / acute_load / sleep_history / stress_history
    percent: int | None = None
    feedback: str | None = None  # good / moderate / poor ...
    value: float | None = None


class TrainingReadinessMetric(ApiModel):
    score: int | None = None
    level: str | None = None  # prime / high / moderate / low / poor
    feedback_short: str | None = None
    feedback_long: str | None = None
    recovery_time_minutes: int | None = None
    measured_at: UtcDatetime | None = None
    # measured_at + recovery_time_minutes: when Garmin considers you fully recovered.
    recovery_until: UtcDatetime | None = None
    factors: list[ReadinessFactor] = []


class LoadFocusPart(ApiModel):
    value: float | None = None  # load accumulated over the last 4 weeks
    target_min: float | None = None
    target_max: float | None = None


class LoadFocus(ApiModel):
    """Garmin's 4-week load focus: how training splits between intensity types."""

    aerobic_low: LoadFocusPart | None = None
    aerobic_high: LoadFocusPart | None = None
    anaerobic: LoadFocusPart | None = None
    feedback: str | None = None  # e.g. AEROBIC_HIGH_SHORTAGE, BALANCED


class TrainingStatusMetric(ApiModel):
    status: str | None = None  # productive / maintaining / recovery / peaking / ...
    feedback_phrase: str | None = None
    vo2_max: float | None = None
    vo2_max_cycling: float | None = None
    acute_load: float | None = None
    chronic_load: float | None = None
    load_ratio: float | None = None
    acwr_status: str | None = None  # low / optimal / high / very_high
    acwr_percent: int | None = None
    # Optimal range for the acute load (Garmin: 0.8x to 1.5x the chronic load).
    optimal_load_min: float | None = None
    optimal_load_max: float | None = None
    load_focus: LoadFocus | None = None


class TrainingDay(ApiModel):
    date: str  # YYYY-MM-DD, local
    count: int = 0
    duration_seconds: float = 0
    distance_meters: float = 0
    training_load: float = 0
    sports: list[str] = []  # activity type keys, in order


class SportTotal(ApiModel):
    type: str
    count: int = 0
    duration_seconds: float = 0
    distance_meters: float = 0


class TrainingWeek(ApiModel):
    """The current week (Monday to Sunday) of workouts, and last week for comparison."""

    week_start: str
    days: list[TrainingDay] = []
    count: int = 0
    duration_seconds: float = 0
    distance_meters: float = 0
    training_load: float = 0
    elevation_gain: float = 0
    previous_week_count: int | None = None
    previous_week_duration_seconds: float | None = None
    previous_week_training_load: float | None = None
    hr_zone_seconds: list[float] = []  # time in heart-rate zones 1 to 5, this week
    sports: list[SportTotal] = []


class PlannedWorkout(ApiModel):
    date: str  # YYYY-MM-DD
    name: str | None = None
    sport: str | None = None  # running, cycling, strength_training...
    intent: str | None = None  # Garmin Coach phrase, e.g. AEROBIC_LOW_SHORTAGE_BASE
    duration_seconds: float | None = None
    distance_meters: float | None = None
    plan_name: str | None = None
    is_rest_day: bool = False
    is_race: bool = False
    completed: bool = False


class IntensityMinutesMetric(ApiModel):
    moderate: int | None = None  # week to date
    vigorous: int | None = None  # week to date
    week_total: int | None = None  # moderate + 2 x vigorous, what Garmin counts
    weekly_goal: int | None = None
    today: int | None = None


class Spo2Metric(ApiModel):
    average: int | None = None
    lowest: int | None = None
    latest: int | None = None


class RespirationMetric(ApiModel):
    waking_avg: float | None = None
    sleep_avg: float | None = None
    lowest: float | None = None
    highest: float | None = None


class Activity(ApiModel):
    id: int
    name: str | None = None
    type: str  # provider type key, e.g. running, cycling, lap_swimming, strength_training
    started_at: UtcDatetime | None = None
    duration_seconds: float | None = None
    moving_seconds: float | None = None
    distance_meters: float | None = None
    calories: float | None = None
    average_hr: int | None = None
    max_hr: int | None = None
    average_speed: float | None = None  # m/s
    elevation_gain: float | None = None  # meters
    aerobic_effect: float | None = None
    anaerobic_effect: float | None = None
    effect_label: str | None = None
    training_load: float | None = None
    vo2_max: float | None = None


class RacePredictions(ApiModel):
    five_k: int | None = None  # seconds
    ten_k: int | None = None
    half_marathon: int | None = None
    marathon: int | None = None


class DashboardSnapshot(ApiModel):
    schema_version: int = SCHEMA_VERSION
    calendar_date: str
    generated_at: UtcDatetime
    # True when Garmin could not be reached and this is the last good snapshot.
    stale: bool = False
    # True when the provider session expired: show the data, but ask to sign in again.
    needs_reauth: bool = False
    source: Source
    unit_system: str | None = None  # metric / statute

    steps: StepsMetric | None = None
    calories: CaloriesMetric | None = None
    floors: FloorsMetric | None = None
    heart_rate: HeartRateMetric | None = None
    body_battery: BodyBatteryMetric | None = None
    stress: StressMetric | None = None
    sleep: SleepMetric | None = None
    hrv: HrvMetric | None = None
    training_readiness: TrainingReadinessMetric | None = None
    training_status: TrainingStatusMetric | None = None
    intensity_minutes: IntensityMinutesMetric | None = None
    spo2: Spo2Metric | None = None
    respiration: RespirationMetric | None = None
    last_activity: Activity | None = None
    recent_activities: list[Activity] = []
    race_predictions: RacePredictions | None = None
    training_week: TrainingWeek | None = None
    upcoming_workouts: list[PlannedWorkout] = []

    # Sections that could not be loaded this time ("hrv", "sleep"...), for diagnostics.
    warnings: list[str] = []

"""Raw Garmin Connect payloads -> provider-agnostic ``DashboardSnapshot``.

Garmin payloads are inconsistent: four timestamp encodings (true UTC epoch ms, "local"
epoch ms, ISO strings without zone, space-separated datetimes), sentinel values (-1/-2
for stress and respiration, null heart rate), descriptor arrays whose key names change
per endpoint, ints that sometimes come as floats. Every helper here is defensive and
every section is built independently: one odd payload drops one card, never the whole
snapshot.

Shapes were checked against real responses for the summary, sleep, stress, heart rate,
respiration and daily steps endpoints; the others follow python-garminconnect's typed
models and are parsed with extra tolerance.
"""

from __future__ import annotations

import logging
import math
import re
from collections.abc import Callable, Iterable
from datetime import UTC, date, datetime, timedelta
from typing import Any

from ...schemas import (
    Activity,
    BodyBatteryMetric,
    CaloriesMetric,
    DailyValue,
    DashboardSnapshot,
    FloorsMetric,
    HeartRateMetric,
    HrvBaseline,
    HrvMetric,
    IntensityMinutesMetric,
    Point,
    ProviderId,
    RacePredictions,
    ReadinessFactor,
    RespirationMetric,
    SleepMetric,
    SleepSegment,
    SleepStage,
    Source,
    Spo2Metric,
    StepsMetric,
    StressMetric,
    TrainingReadinessMetric,
    TrainingStatusMetric,
)

logger = logging.getLogger(__name__)

BUCKET_SECONDS = 15 * 60  # intraday series are averaged into 15-minute buckets
SLEEP_LEVELS = {0: SleepStage.deep, 1: SleepStage.light, 2: SleepStage.rem, 3: SleepStage.awake}
_PHRASE_SUFFIX = re.compile(r"_\d+$")

# --------------------------------------------------------------------------- primitives


def num(value: Any) -> float | None:
    """A finite number, or None (booleans, sentinels as strings, NaN... are rejected)."""
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int | float):
        return float(value) if math.isfinite(value) else None
    if isinstance(value, str):
        try:
            parsed = float(value)
        except ValueError:
            return None
        return parsed if math.isfinite(parsed) else None
    return None


def integer(value: Any) -> int | None:
    parsed = num(value)
    return round(parsed) if parsed is not None else None


def positive(value: Any) -> float | None:
    """Garmin uses negative values (-1, -2) as 'no reading' sentinels."""
    parsed = num(value)
    return parsed if parsed is not None and parsed >= 0 else None


def text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def key(value: Any) -> str | None:
    """Normalize an enum-like string (``"BALANCED"`` -> ``"balanced"``), dropping unknowns."""
    raw = text(value)
    if raw is None or raw.upper() in {"UNKNOWN", "NONE", "NULL", "NO_DATA", "N/A"}:
        return None
    return raw.lower()


def dig(data: Any, *path: str | int) -> Any:
    for part in path:
        if isinstance(part, int):
            if not isinstance(data, list) or not -len(data) <= part < len(data):
                return None
            data = data[part]
        else:
            if not isinstance(data, dict):
                return None
            data = data.get(part)
    return data


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def first(*values: Any) -> Any:
    return next((v for v in values if v is not None), None)


def parse_gmt(value: Any) -> datetime | None:
    """Parse a Garmin *GMT* timestamp: epoch ms/s, or an ISO-ish string without zone."""
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int | float):
        seconds = value / 1000 if value > 10**11 else value
        try:
            return datetime.fromtimestamp(seconds, UTC).replace(microsecond=0)
        except (OverflowError, OSError, ValueError):
            return None
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC).replace(microsecond=0)
    return None


def epoch(value: Any) -> int | None:
    parsed = parse_gmt(value)
    return int(parsed.timestamp()) if parsed else None


def index_map(descriptors: Any, defaults: dict[str, int]) -> dict[str, int]:
    """Map descriptor keys to array indexes, whatever the endpoint calls its fields."""
    mapping = dict(defaults)
    for descriptor in as_list(descriptors):
        if not isinstance(descriptor, dict):
            continue
        idx = next((v for k, v in descriptor.items() if k.lower().endswith("index")), None)
        name = next((v for k, v in descriptor.items() if k.lower().endswith("key")), None)
        if isinstance(idx, int) and isinstance(name, str):
            mapping[name] = idx
    return mapping


def samples(
    rows: Any, ts_index: int, value_index: int, *, valid: Callable[[Any], float | None] = positive
) -> list[tuple[int, float]]:
    """``[[ts_ms, ..., value], ...]`` -> sorted ``(epoch_seconds, value)`` without sentinels."""
    out: list[tuple[int, float]] = []
    for row in as_list(rows):
        if not isinstance(row, list | tuple) or len(row) <= max(ts_index, value_index):
            continue
        ts, value = epoch(row[ts_index]), valid(row[value_index])
        if ts is not None and value is not None:
            out.append((ts, value))
    out.sort()
    return out


def bucket(points: Iterable[tuple[int, float]], *, mode: str = "mean") -> list[Point]:
    """Downsample to fixed buckets: compact for widgets, smooth enough for sparklines."""
    groups: dict[int, list[float]] = {}
    for ts, value in points:
        groups.setdefault(ts - ts % BUCKET_SECONDS, []).append(value)
    result = []
    for start in sorted(groups):
        values = groups[start]
        value = values[-1] if mode == "last" else sum(values) / len(values)
        result.append(Point(t=start, v=round(value, 1)))
    return result


def phrase_key(value: Any) -> str | None:
    """``"PRODUCTIVE_6"`` -> ``"productive"`` (Garmin appends a variant number)."""
    raw = text(value)
    return key(_PHRASE_SUFFIX.sub("", raw)) if raw else None


def _section[T](name: str, build: Callable[[], T], warnings: list[str]) -> T | None:
    try:
        return build()
    except Exception:  # a malformed payload must not take the whole snapshot down
        logger.exception("Could not normalize Garmin section %s", name)
        warnings.append(f"{name}: unreadable")
        return None


# ---------------------------------------------------------------------------- sections


def build_snapshot(
    data: dict[str, Any],
    *,
    day: date,
    unit_system: str | None,
    warnings: list[str] | None = None,
    now: datetime | None = None,
) -> DashboardSnapshot:
    warnings = list(warnings or [])
    summary = as_dict(data.get("summary"))
    sleep_raw = as_dict(data.get("sleep"))
    sleep_rows = sleep_history_rows(data.get("sleep_history"))

    activities = _section("activities", lambda: build_activities(data.get("activities")), warnings)
    return DashboardSnapshot(
        calendar_date=day.isoformat(),
        generated_at=(now or datetime.now(UTC)).replace(microsecond=0),
        source=_section("source", lambda: build_source(summary, data.get("device")), warnings)
        or Source(provider=ProviderId.garmin),
        unit_system=key(unit_system),
        steps=_section("steps", lambda: build_steps(summary, data.get("steps_history")), warnings),
        calories=_section("calories", lambda: build_calories(summary), warnings),
        floors=_section("floors", lambda: build_floors(summary), warnings),
        heart_rate=_section(
            "heart_rate",
            lambda: build_heart_rate(summary, data.get("heart_rates"), data.get("rhr_history")),
            warnings,
        ),
        body_battery=_section(
            "body_battery", lambda: build_body_battery(summary, data.get("stress")), warnings
        ),
        stress=_section("stress", lambda: build_stress(summary, data.get("stress")), warnings),
        sleep=_section("sleep", lambda: build_sleep(sleep_raw, sleep_rows, day), warnings),
        hrv=_section(
            "hrv",
            lambda: build_hrv(data.get("hrv"), sleep_raw, sleep_rows, data.get("hrv_history"), day),
            warnings,
        ),
        training_readiness=_section(
            "training_readiness", lambda: build_readiness(data.get("readiness")), warnings
        ),
        training_status=_section(
            "training_status", lambda: build_training_status(data.get("training_status")), warnings
        ),
        intensity_minutes=_section(
            "intensity_minutes",
            lambda: build_intensity(summary, data.get("intensity_week"), day),
            warnings,
        ),
        spo2=_section("spo2", lambda: build_spo2(summary), warnings),
        respiration=_section(
            "respiration", lambda: build_respiration(summary, sleep_raw), warnings
        ),
        last_activity=activities[0] if activities else None,
        recent_activities=activities or [],
        race_predictions=_section(
            "race_predictions",
            lambda: build_race_predictions(data.get("race_predictions")),
            warnings,
        ),
        warnings=warnings,
    )


def build_source(summary: dict[str, Any], device: Any) -> Source:
    device = as_dict(device)
    last_sync = parse_gmt(summary.get("lastSyncTimestampGMT")) or parse_gmt(
        first(device.get("lastUsedDeviceUploadTime"), device.get("lastUploadTime"))
    )
    return Source(
        provider=ProviderId.garmin,
        device_name=text(
            first(
                device.get("lastUsedDeviceName"),
                device.get("deviceName"),
                device.get("productDisplayName"),
                device.get("displayName"),
            )
        ),
        device_image_url=text(first(device.get("imageUrl"), device.get("imageURL"))),
        last_sync_at=last_sync,
    )


def build_steps(summary: dict[str, Any], history_raw: Any) -> StepsMetric | None:
    history = [
        DailyValue(
            date=row["calendarDate"],
            value=num(row.get("totalSteps")),
            goal=num(row.get("stepGoal")),
        )
        for row in as_list(history_raw)
        if isinstance(row, dict) and isinstance(row.get("calendarDate"), str)
    ]
    count = integer(summary.get("totalSteps"))
    goal = integer(summary.get("dailyStepGoal"))
    distance = num(first(summary.get("totalDistanceMeters"), summary.get("wellnessDistanceMeters")))
    if count is None and history:  # summary unavailable: fall back to the history row
        today = history[-1]
        count, goal = integer(today.value), integer(today.goal)
    if count is None:
        return None
    if history and summary.get("calendarDate") == history[-1].date:
        history[-1] = history[-1].model_copy(update={"value": float(count), "goal": goal})
    return StepsMetric(count=count, goal=goal, distance_meters=distance, history=history)


def build_calories(summary: dict[str, Any]) -> CaloriesMetric | None:
    total = integer(first(summary.get("totalKilocalories"), summary.get("wellnessKilocalories")))
    active = integer(
        first(summary.get("activeKilocalories"), summary.get("wellnessActiveKilocalories"))
    )
    if total is None and active is None:
        return None
    return CaloriesMetric(
        total=total, active=active, resting=integer(summary.get("bmrKilocalories"))
    )


def build_floors(summary: dict[str, Any]) -> FloorsMetric | None:
    ascended = num(summary.get("floorsAscended"))
    if ascended is None:
        return None
    return FloorsMetric(
        ascended=round(ascended, 1), goal=num(summary.get("userFloorsAscendedGoal"))
    )


def build_heart_rate(
    summary: dict[str, Any], hr_raw: Any, rhr_history: Any
) -> HeartRateMetric | None:
    hr = as_dict(hr_raw)
    idx = index_map(hr.get("heartRateValueDescriptors"), {"timestamp": 0, "heartrate": 1})
    points = samples(hr.get("heartRateValues"), idx["timestamp"], idx["heartrate"])
    history = [
        DailyValue(date=row["calendarDate"], value=num(row.get("value")))
        for row in as_list(rhr_history)
        if isinstance(row, dict) and isinstance(row.get("calendarDate"), str)
    ]
    resting = integer(first(summary.get("restingHeartRate"), hr.get("restingHeartRate")))
    metric = HeartRateMetric(
        resting=resting,
        # The summary's min/max are instantaneous; the HR endpoint's are 2-min averages.
        min=integer(first(summary.get("minHeartRate"), hr.get("minHeartRate"))),
        max=integer(first(summary.get("maxHeartRate"), hr.get("maxHeartRate"))),
        resting_seven_day_avg=integer(
            first(
                summary.get("lastSevenDaysAvgRestingHeartRate"),
                hr.get("lastSevenDaysAvgRestingHeartRate"),
            )
        ),
        latest=round(points[-1][1]) if points else None,
        series=bucket(points),
        history=history,
    )
    if metric.resting is None and not metric.series:
        return None
    return metric


def build_body_battery(summary: dict[str, Any], stress_raw: Any) -> BodyBatteryMetric | None:
    stress = as_dict(stress_raw)
    idx = index_map(
        stress.get("bodyBatteryValueDescriptorsDTOList"),
        {"timestamp": 0, "bodyBatteryLevel": 2},
    )
    points = samples(
        stress.get("bodyBatteryValuesArray"), idx["timestamp"], idx["bodyBatteryLevel"]
    )
    current = integer(summary.get("bodyBatteryMostRecentValue"))
    if current is None and points:
        current = round(points[-1][1])
    if current is None and not points:
        return None
    return BodyBatteryMetric(
        current=current,
        highest=integer(summary.get("bodyBatteryHighestValue")),
        lowest=integer(summary.get("bodyBatteryLowestValue")),
        charged=integer(summary.get("bodyBatteryChargedValue")),
        drained=integer(summary.get("bodyBatteryDrainedValue")),
        at_wake=integer(summary.get("bodyBatteryAtWakeTime")),
        series=bucket(points, mode="last"),
    )


def build_stress(summary: dict[str, Any], stress_raw: Any) -> StressMetric | None:
    stress = as_dict(stress_raw)
    idx = index_map(stress.get("stressValueDescriptorsDTOList"), {"timestamp": 0, "stressLevel": 1})
    points = samples(stress.get("stressValuesArray"), idx["timestamp"], idx["stressLevel"])
    average = integer(
        positive(first(summary.get("averageStressLevel"), stress.get("avgStressLevel")))
    )
    if average is None and not points:
        return None
    return StressMetric(
        average=average,
        max=integer(positive(first(summary.get("maxStressLevel"), stress.get("maxStressLevel")))),
        current=round(points[-1][1]) if points else None,
        qualifier=key(summary.get("stressQualifier")),
        rest_seconds=integer(summary.get("restStressDuration")),
        low_seconds=integer(summary.get("lowStressDuration")),
        medium_seconds=integer(summary.get("mediumStressDuration")),
        high_seconds=integer(summary.get("highStressDuration")),
        series=bucket(points),
    )


def sleep_history_rows(raw: Any) -> list[dict[str, Any]]:
    """Rows of ``get_sleep_daily``: ``{calendarDate, values: {...}}`` (or flat rows)."""
    rows = []
    for row in as_list(raw):
        if not isinstance(row, dict) or not isinstance(row.get("calendarDate"), str):
            continue
        values = as_dict(row.get("values")) or row
        rows.append({"calendarDate": row["calendarDate"], **values})
    return rows


def _segments(levels: Any) -> list[SleepSegment]:
    segments: list[SleepSegment] = []
    for level in as_list(levels):
        if not isinstance(level, dict):
            continue
        start, end = epoch(level.get("startGMT")), epoch(level.get("endGMT"))
        code = integer(level.get("activityLevel"))
        stage = SLEEP_LEVELS.get(code) if code is not None else None
        if start is None or end is None or end <= start or stage is None:
            continue
        if segments and segments[-1].stage == stage and segments[-1].end == start:
            segments[-1] = segments[-1].model_copy(update={"end": end})
        else:
            segments.append(SleepSegment(start=start, end=end, stage=stage))
    segments.sort(key=lambda s: s.start)
    return segments


def build_sleep(
    raw: dict[str, Any], history_rows: list[dict[str, Any]], day: date
) -> SleepMetric | None:
    dto = as_dict(raw.get("dailySleepDTO"))
    duration = integer(dto.get("sleepTimeSeconds"))
    history = [
        DailyValue(
            date=row["calendarDate"],
            value=num(first(row.get("sleepScore"), dig(row, "sleepScores", "overall", "value"))),
        )
        for row in history_rows
    ]
    if not duration:
        return None
    score = integer(dig(dto, "sleepScores", "overall", "value"))
    calendar = text(dto.get("calendarDate")) or day.isoformat()
    if score is not None:
        history = [h for h in history if h.date != calendar] + [
            DailyValue(date=calendar, value=float(score))
        ]
        history.sort(key=lambda h: h.date)
    need_minutes = num(dig(dto, "sleepNeed", "actual"))
    return SleepMetric(
        calendar_date=calendar,
        score=score,
        quality=key(dig(dto, "sleepScores", "overall", "qualifierKey")),
        duration_seconds=duration,
        deep_seconds=integer(dto.get("deepSleepSeconds")),
        light_seconds=integer(dto.get("lightSleepSeconds")),
        rem_seconds=integer(dto.get("remSleepSeconds")),
        awake_seconds=integer(dto.get("awakeSleepSeconds")),
        nap_seconds=integer(dto.get("napTimeSeconds")) or None,
        start=parse_gmt(dto.get("sleepStartTimestampGMT")),
        end=parse_gmt(dto.get("sleepEndTimestampGMT")),
        need_seconds=round(need_minutes * 60) if need_minutes else None,
        avg_overnight_hrv=positive(raw.get("avgOvernightHrv")),
        resting_heart_rate=integer(raw.get("restingHeartRate")),
        avg_respiration=positive(dto.get("averageRespirationValue")),
        avg_spo2=positive(dto.get("averageSpO2Value")),
        avg_stress=positive(dto.get("avgSleepStress")),
        body_battery_change=integer(raw.get("bodyBatteryChange")),
        feedback=key(dto.get("sleepScoreFeedback")),
        stages=_segments(raw.get("sleepLevels")),
        history=history,
    )


def build_hrv(
    hrv_raw: Any,
    sleep_raw: dict[str, Any],
    sleep_rows: list[dict[str, Any]],
    range_raw: Any,
    day: date,
) -> HrvMetric | None:
    hrv = as_dict(hrv_raw)
    summary = as_dict(hrv.get("hrvSummary"))
    baseline = as_dict(summary.get("baseline"))

    # Readings: the sleep payload carries the same 5-min samples in a verified shape.
    readings = [
        (ts, value)
        for item in as_list(sleep_raw.get("hrvData"))
        if isinstance(item, dict)
        and (ts := epoch(item.get("startGMT"))) is not None
        and (value := positive(item.get("value"))) is not None
    ]
    if not readings:
        readings = [
            (ts, value)
            for item in as_list(hrv.get("hrvReadings"))
            if isinstance(item, dict)
            and (ts := epoch(first(item.get("readingTimeGMT"), item.get("readingTimeGmt"))))
            is not None
            and (value := positive(first(item.get("hrvValue"), item.get("value")))) is not None
        ]
    readings.sort()

    history = [
        DailyValue(date=row["calendarDate"], value=positive(row.get("avgOvernightHrv")))
        for row in sleep_rows
        if positive(row.get("avgOvernightHrv")) is not None
    ]
    if not history:
        history = [
            DailyValue(date=row["calendarDate"], value=positive(row.get("lastNightAvg")))
            for row in as_list(as_dict(range_raw).get("hrvSummaries"))
            if isinstance(row, dict)
            and isinstance(row.get("calendarDate"), str)
            and positive(row.get("lastNightAvg")) is not None
        ]

    last_night = integer(
        first(positive(summary.get("lastNightAvg")), positive(sleep_raw.get("avgOvernightHrv")))
    )
    if last_night is not None:
        history = [h for h in history if h.date != day.isoformat()] + [
            DailyValue(date=day.isoformat(), value=float(last_night))
        ]
        history.sort(key=lambda h: h.date)

    metric = HrvMetric(
        last_night_avg=last_night,
        last_night_high=integer(positive(summary.get("lastNight5MinHigh"))),
        weekly_avg=integer(positive(summary.get("weeklyAvg"))),
        status=key(first(summary.get("status"), sleep_raw.get("hrvStatus"))),
        feedback=text(summary.get("feedbackPhrase")),
        baseline=HrvBaseline(
            low_upper=integer(baseline.get("lowUpper")),
            balanced_low=integer(baseline.get("balancedLow")),
            balanced_upper=integer(baseline.get("balancedUpper")),
        )
        if baseline
        else None,
        readings=[Point(t=ts, v=round(value, 1)) for ts, value in readings[:200]],
        history=history,
    )
    if metric.last_night_avg is None and metric.weekly_avg is None:
        return None
    return metric


_READINESS_FACTORS = (
    ("sleep", "sleepScoreFactorPercent", "sleepScoreFactorFeedback", "sleepScore"),
    ("recovery_time", "recoveryTimeFactorPercent", "recoveryTimeFactorFeedback", "recoveryTime"),
    ("hrv", "hrvFactorPercent", "hrvFactorFeedback", "hrvWeeklyAverage"),
    ("acute_load", "acwrFactorPercent", "acwrFactorFeedback", "acuteLoad"),
    ("sleep_history", "sleepHistoryFactorPercent", "sleepHistoryFactorFeedback", None),
    ("stress_history", "stressHistoryFactorPercent", "stressHistoryFactorFeedback", None),
)


def build_readiness(raw: Any) -> TrainingReadinessMetric | None:
    entries = [
        e
        for e in (as_list(raw) or [raw])
        if isinstance(e, dict) and num(e.get("score")) is not None
    ]
    if not entries:
        return None
    epoch_min = datetime.min.replace(tzinfo=UTC)
    latest = max(entries, key=lambda e: parse_gmt(e.get("timestamp")) or epoch_min)
    factors = []
    for name, percent_key, feedback_key, value_key in _READINESS_FACTORS:
        feedback = key(latest.get(feedback_key))
        percent = integer(latest.get(percent_key))
        if feedback is None and not percent:
            continue
        factors.append(
            ReadinessFactor(
                key=name,
                percent=percent,
                feedback=feedback,
                value=num(latest.get(value_key)) if value_key else None,
            )
        )
    return TrainingReadinessMetric(
        score=integer(latest.get("score")),
        level=key(latest.get("level")),
        feedback_short=text(latest.get("feedbackShort")),
        feedback_long=text(latest.get("feedbackLong")),
        recovery_time_minutes=integer(latest.get("recoveryTime")),
        measured_at=parse_gmt(latest.get("timestamp")),
        factors=factors,
    )


def _primary(mapping: Any) -> dict[str, Any]:
    """Training metrics are keyed by device id: pick the primary training device."""
    candidates = [v for v in as_dict(mapping).values() if isinstance(v, dict)]
    return next((c for c in candidates if c.get("primaryTrainingDevice")), None) or (
        candidates[0] if candidates else {}
    )


def build_training_status(raw: Any) -> TrainingStatusMetric | None:
    data = as_dict(raw)
    vo2 = as_dict(dig(data, "mostRecentVO2Max", "generic"))
    vo2_cycling = as_dict(dig(data, "mostRecentVO2Max", "cycling"))
    status = _primary(dig(data, "mostRecentTrainingStatus", "latestTrainingStatusData"))
    load = as_dict(status.get("acuteTrainingLoadDTO"))
    metric = TrainingStatusMetric(
        status=phrase_key(status.get("trainingStatusFeedbackPhrase")),
        feedback_phrase=text(status.get("trainingStatusFeedbackPhrase")),
        vo2_max=num(first(vo2.get("vo2MaxPreciseValue"), vo2.get("vo2MaxValue"))),
        vo2_max_cycling=num(
            first(vo2_cycling.get("vo2MaxPreciseValue"), vo2_cycling.get("vo2MaxValue"))
        ),
        acute_load=num(load.get("dailyTrainingLoadAcute")),
        chronic_load=num(load.get("dailyTrainingLoadChronic")),
        load_ratio=num(load.get("dailyAcuteChronicWorkloadRatio")),
        acwr_status=key(load.get("acwrStatus")),
    )
    if not any(metric.model_dump(exclude_none=True).values()):
        return None
    return metric


def build_intensity(
    summary: dict[str, Any], weekly_raw: Any, day: date
) -> IntensityMinutesMetric | None:
    monday = (day - timedelta(days=day.weekday())).isoformat()
    rows = [r for r in as_list(weekly_raw) if isinstance(r, dict)]
    week = next((r for r in rows if r.get("calendarDate") == monday), rows[-1] if rows else {})
    moderate, vigorous = integer(week.get("moderateValue")), integer(week.get("vigorousValue"))
    today_moderate = integer(summary.get("moderateIntensityMinutes"))
    today_vigorous = integer(summary.get("vigorousIntensityMinutes"))
    goal = integer(first(week.get("weeklyGoal"), summary.get("intensityMinutesGoal")))
    if moderate is None and vigorous is None and today_moderate is None:
        return None
    today = None
    if today_moderate is not None or today_vigorous is not None:
        today = (today_moderate or 0) + 2 * (today_vigorous or 0)
    week_total = None
    if moderate is not None or vigorous is not None:
        week_total = (moderate or 0) + 2 * (vigorous or 0)  # vigorous minutes count double
    return IntensityMinutesMetric(
        moderate=moderate, vigorous=vigorous, week_total=week_total, weekly_goal=goal, today=today
    )


def build_spo2(summary: dict[str, Any]) -> Spo2Metric | None:
    metric = Spo2Metric(
        average=integer(positive(summary.get("averageSpo2"))),
        lowest=integer(positive(summary.get("lowestSpo2"))),
        latest=integer(positive(summary.get("latestSpo2"))),
    )
    return metric if metric.average is not None or metric.latest is not None else None


def build_respiration(
    summary: dict[str, Any], sleep_raw: dict[str, Any]
) -> RespirationMetric | None:
    metric = RespirationMetric(
        waking_avg=positive(summary.get("avgWakingRespirationValue")),
        sleep_avg=positive(dig(sleep_raw, "dailySleepDTO", "averageRespirationValue")),
        lowest=positive(summary.get("lowestRespirationValue")),
        highest=positive(summary.get("highestRespirationValue")),
    )
    return metric if metric.waking_avg is not None or metric.sleep_avg is not None else None


def build_activities(raw: Any) -> list[Activity]:
    items = as_list(raw) or as_list(as_dict(raw).get("activityList"))
    activities = []
    for item in items:
        if not isinstance(item, dict) or integer(item.get("activityId")) is None:
            continue
        activity_type = item.get("activityType")
        type_key = text(
            dig(activity_type, "typeKey") if isinstance(activity_type, dict) else activity_type
        )
        activities.append(
            Activity(
                id=integer(item.get("activityId")) or 0,
                name=text(item.get("activityName")),
                type=(type_key or "other").lower(),
                started_at=parse_gmt(item.get("startTimeGMT")),
                duration_seconds=positive(first(item.get("duration"), item.get("elapsedDuration"))),
                moving_seconds=positive(item.get("movingDuration")),
                distance_meters=positive(item.get("distance")) or None,
                calories=positive(item.get("calories")),
                average_hr=integer(positive(item.get("averageHR"))),
                max_hr=integer(positive(item.get("maxHR"))),
                average_speed=positive(item.get("averageSpeed")) or None,
                elevation_gain=positive(item.get("elevationGain")),
                aerobic_effect=positive(item.get("aerobicTrainingEffect")),
                anaerobic_effect=positive(item.get("anaerobicTrainingEffect")),
                effect_label=text(item.get("trainingEffectLabel")),
                training_load=positive(item.get("activityTrainingLoad")),
                vo2_max=positive(item.get("vO2MaxValue")),
            )
        )
    activities.sort(key=lambda a: a.started_at or datetime.min.replace(tzinfo=UTC), reverse=True)
    return activities


def build_race_predictions(raw: Any) -> RacePredictions | None:
    data = raw[-1] if isinstance(raw, list) and raw else as_dict(raw)
    data = as_dict(data)
    metric = RacePredictions(
        five_k=integer(positive(data.get("time5K"))),
        ten_k=integer(positive(data.get("time10K"))),
        half_marathon=integer(positive(data.get("timeHalfMarathon"))),
        marathon=integer(positive(data.get("timeMarathon"))),
    )
    return metric if any(metric.model_dump(exclude_none=True).values()) else None

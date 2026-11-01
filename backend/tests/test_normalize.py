from __future__ import annotations

import json
from datetime import UTC, date, datetime

import pytest

from healthwidgets.providers.garmin import normalize
from healthwidgets.providers.garmin.normalize import build_snapshot, parse_gmt
from healthwidgets.schemas import DashboardSnapshot

from . import garmin_payloads as raw

DAY = date(2026, 1, 14)


@pytest.fixture
def snapshot() -> DashboardSnapshot:
    return build_snapshot(
        raw.bundle(), day=DAY, unit_system="metric", activity_zones=raw.hr_zones()
    )


def test_daily_totals(snapshot: DashboardSnapshot) -> None:
    assert snapshot.calendar_date == "2026-01-14"
    assert snapshot.steps.count == 9312
    assert snapshot.steps.goal == 10000
    assert snapshot.steps.distance_meters == 7420
    # The live summary value wins over the (lagging) history row for the same day.
    assert snapshot.steps.history[-1].value == 9312
    assert len(snapshot.steps.history) == 7
    assert snapshot.calories.total == 2564 and snapshot.calories.active == 712
    assert snapshot.floors.ascended == 12.8 and snapshot.floors.goal == 10
    assert snapshot.spo2.average == 95 and snapshot.spo2.lowest == 88
    assert snapshot.respiration.waking_avg == 15.0 and snapshot.respiration.sleep_avg == 14.0


def test_heart_rate_skips_nulls_and_buckets(snapshot: DashboardSnapshot) -> None:
    hr = snapshot.heart_rate
    assert hr.resting == 52 and hr.resting_seven_day_avg == 53
    assert hr.min == 47 and hr.max == 163  # instantaneous extremes from the summary
    assert hr.latest == 66
    # The valid samples of the first 15 minutes are averaged into one bucket.
    assert hr.series[0].v == pytest.approx((61 + 59 + 60) / 3, abs=0.1)
    assert hr.series[0].t == raw.MIDNIGHT_MS // 1000
    assert [h.value for h in hr.history] == [53, 51, 52]


def test_stress_drops_sentinels(snapshot: DashboardSnapshot) -> None:
    stress = snapshot.stress
    assert stress.average == 31 and stress.max == 88
    assert stress.qualifier == "balanced"
    assert all(point.v >= 0 for point in stress.series)
    assert stress.series[0].v == pytest.approx((16 + 19 + 22) / 3, abs=0.1)
    assert stress.current == 37


def test_body_battery_series_comes_from_stress_payload(snapshot: DashboardSnapshot) -> None:
    bb = snapshot.body_battery
    assert (bb.current, bb.highest, bb.lowest, bb.charged, bb.drained, bb.at_wake) == (
        21,
        91,
        21,
        61,
        70,
        91,
    )
    assert bb.series[0].v == 35  # "last" sample of the bucket for a level
    assert bb.series[-1].v == 21


def test_sleep(snapshot: DashboardSnapshot) -> None:
    sleep = snapshot.sleep
    assert sleep.score == 84 and sleep.quality == "good"
    assert sleep.duration_seconds == 27600
    assert (sleep.deep_seconds, sleep.light_seconds, sleep.rem_seconds, sleep.awake_seconds) == (
        6000,
        15360,
        6240,
        1080,
    )
    assert sleep.start == datetime(2026, 1, 13, 22, 52, 10, tzinfo=UTC)
    assert sleep.end == datetime(2026, 1, 14, 6, 50, 10, tzinfo=UTC)
    assert sleep.need_seconds == 470 * 60
    assert sleep.avg_overnight_hrv == 62.0
    assert sleep.feedback == "positive_long_and_deep"
    stages = [segment.stage.value for segment in sleep.stages]
    # Consecutive "light" segments are merged.
    assert stages == ["light", "deep", "awake", "light", "rem", "light"]
    assert sleep.stages[0].start == raw.SLEEP_START_MS // 1000
    assert [h.value for h in sleep.history] == [79, 81, 84]  # today's score replaces the row


def test_hrv(snapshot: DashboardSnapshot) -> None:
    hrv = snapshot.hrv
    assert (hrv.last_night_avg, hrv.last_night_high, hrv.weekly_avg) == (62, 88, 60)
    assert hrv.status == "balanced" and hrv.feedback == "HRV_BALANCED_4"
    assert (hrv.baseline.low_upper, hrv.baseline.balanced_low, hrv.baseline.balanced_upper) == (
        52,
        57,
        71,
    )
    assert [r.v for r in hrv.readings] == [58, 63, 66]  # verified shape from the sleep payload
    assert [h.value for h in hrv.history] == [59, 61, 62]


def test_readiness_uses_latest_snapshot(snapshot: DashboardSnapshot) -> None:
    readiness = snapshot.training_readiness
    assert readiness.score == 88 and readiness.level == "high"
    assert readiness.recovery_time_minutes == 412
    assert readiness.feedback_short == "WELL_RECOVERED"
    factors = {f.key: f for f in readiness.factors}
    assert set(factors) == {
        "sleep",
        "recovery_time",
        "hrv",
        "acute_load",
        "sleep_history",
        "stress_history",
    }
    assert factors["sleep"].percent == 86 and factors["sleep"].value == 84
    assert factors["acute_load"].feedback == "very_good"


def test_training_status_picks_primary_device(snapshot: DashboardSnapshot) -> None:
    status = snapshot.training_status
    assert status.status == "productive"
    assert status.feedback_phrase == "PRODUCTIVE_3"
    assert status.vo2_max == 51.3
    assert (status.acute_load, status.chronic_load, status.load_ratio) == (412, 388, 1.1)
    assert status.acwr_status == "optimal"


def test_training_load_optimal_range_and_focus(snapshot: DashboardSnapshot) -> None:
    status = snapshot.training_status
    assert status.acwr_percent == 41
    assert (status.optimal_load_min, status.optimal_load_max) == (310.4, 582.0)
    focus = status.load_focus
    assert focus.feedback == "AEROBIC_HIGH_SHORTAGE"
    assert focus.aerobic_low.value == 512.3
    assert (focus.aerobic_low.target_min, focus.aerobic_low.target_max) == (380, 690)
    assert (focus.anaerobic.value, focus.anaerobic.target_max) == (98.7, 210)


def test_recovery_until(snapshot: DashboardSnapshot) -> None:
    readiness = snapshot.training_readiness
    assert readiness.measured_at == datetime(2026, 1, 14, 19, 42, 10, tzinfo=UTC)
    assert readiness.recovery_until == datetime(2026, 1, 15, 2, 34, 10, tzinfo=UTC)  # +412 min


def test_training_week(snapshot: DashboardSnapshot) -> None:
    week = snapshot.training_week
    assert week.week_start == "2026-01-12"
    assert week.days[0].date == "2026-01-12" and len(week.days) == 7
    assert [d.count for d in week.days] == [1, 1, 1, 0, 0, 0, 0]
    assert week.days[1].sports == ["cycling"]
    assert week.count == 3
    assert week.duration_seconds == round(2711.4 + 3600.0 + 2588.6)
    assert week.distance_meters == 38912.3
    assert week.training_load == 266.4
    assert week.elevation_gain == 274
    # Only last week counts as "previous" (the 2026-01-03 run is older).
    assert (week.previous_week_count, week.previous_week_duration_seconds) == (1, 5400)
    assert week.previous_week_training_load == 180
    # Strength has no zones: running + cycling only.
    assert week.hr_zone_seconds == [900, 4200, 900, 150, 39]
    assert [s.type for s in week.sports] == ["cycling", "strength_training", "running"]


def test_training_week_unavailable_is_none() -> None:
    data = raw.bundle()
    data["week_activities"] = None
    assert build_snapshot(data, day=DAY, unit_system="metric").training_week is None


def test_upcoming_workouts_merge_calendar_and_plan(snapshot: DashboardSnapshot) -> None:
    workouts = snapshot.upcoming_workouts
    assert [w.date for w in workouts] == [
        "2026-01-14",
        "2026-01-15",
        "2026-01-16",
        "2026-01-17",
        "2026-01-18",
    ]
    today = workouts[0]
    assert today.name == "Tempo 3x10" and today.sport == "running"
    assert (today.duration_seconds, today.distance_meters, today.completed) == (3300, 9500.0, False)
    base = workouts[1]
    assert base.sport == "running" and base.intent == "AEROBIC_LOW_SHORTAGE_BASE"
    assert base.plan_name == "Half Marathon"
    assert workouts[3].is_rest_day and workouts[4].is_race


def test_intensity_minutes_count_vigorous_twice(snapshot: DashboardSnapshot) -> None:
    im = snapshot.intensity_minutes
    assert (im.moderate, im.vigorous, im.weekly_goal) == (84, 31, 150)
    assert im.week_total == 84 + 2 * 31
    assert im.today == 18 + 2 * 11


def test_activities_sorted_newest_first(snapshot: DashboardSnapshot) -> None:
    last = snapshot.last_activity
    assert last.type == "strength_training"
    assert last.started_at == datetime(2026, 1, 14, 11, 31, 5, tzinfo=UTC)
    assert last.distance_meters is None  # 0 m strength session
    run = snapshot.recent_activities[1]
    assert run.type == "running" and run.distance_meters == 8412.3 and run.vo2_max == 51.0


def test_source_and_predictions(snapshot: DashboardSnapshot) -> None:
    assert snapshot.source.device_name == "Forerunner 965"
    assert snapshot.source.last_sync_at == datetime(2026, 1, 14, 6, 58, 12, tzinfo=UTC)
    assert snapshot.race_predictions.five_k == 1395
    assert snapshot.race_predictions.marathon == 13690
    assert snapshot.warnings == []


def test_json_contract_is_camel_case_and_ios_friendly(snapshot: DashboardSnapshot) -> None:
    payload = json.loads(snapshot.model_dump_json(by_alias=True))
    assert payload["schemaVersion"] == 1
    assert payload["heartRate"]["restingSevenDayAvg"] == 53
    assert payload["racePredictions"]["fiveK"] == 1395
    # Swift's .iso8601 strategy rejects fractional seconds: make sure there are none.
    assert payload["source"]["lastSyncAt"] == "2026-01-14T06:58:12Z"
    assert payload["sleep"]["start"] == "2026-01-13T22:52:10Z"


def test_empty_day_produces_an_empty_but_valid_snapshot() -> None:
    snapshot = build_snapshot({}, day=DAY, unit_system=None)
    assert snapshot.steps is None and snapshot.sleep is None and snapshot.hrv is None
    assert snapshot.recent_activities == []
    assert snapshot.warnings == []


def test_garbage_never_raises() -> None:
    garbage = {
        "summary": {"totalSteps": "lots", "restingHeartRate": True, "averageStressLevel": -1},
        "sleep": {
            "dailySleepDTO": {"sleepTimeSeconds": 3600, "sleepScores": []},
            "sleepLevels": "x",
        },
        "stress": {"stressValuesArray": [[None, 5], "bad", [1, 2, 3]]},
        "heart_rates": [],
        "readiness": {"score": None},
        "training_status": {"mostRecentTrainingStatus": {"latestTrainingStatusData": []}},
        "activities": [{"activityId": "x"}, {"activityId": 5, "activityType": "running"}],
        "race_predictions": [],
        "intensity_week": {"weird": True},
        "steps_history": [{"calendarDate": 3}],
    }
    snapshot = build_snapshot(garbage, day=DAY, unit_system="metric")
    assert snapshot.steps is None
    assert snapshot.sleep.duration_seconds == 3600 and snapshot.sleep.score is None
    assert snapshot.last_activity.id == 5 and snapshot.last_activity.type == "running"
    DashboardSnapshot.model_validate_json(snapshot.model_dump_json(by_alias=True))


def test_one_broken_section_does_not_break_the_others(monkeypatch: pytest.MonkeyPatch) -> None:
    def explode(*_: object) -> None:
        raise RuntimeError("boom")

    monkeypatch.setattr(normalize, "build_hrv", explode)
    snapshot = build_snapshot(raw.bundle(), day=DAY, unit_system="metric")
    assert snapshot.hrv is None
    assert snapshot.sleep is not None
    assert snapshot.warnings == ["hrv: unreadable"]


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (1768345200000, datetime(2026, 1, 13, 23, 0, tzinfo=UTC)),
        ("2026-01-13T22:52:10.0", datetime(2026, 1, 13, 22, 52, 10, tzinfo=UTC)),
        ("2026-01-14T06:58:12.417", datetime(2026, 1, 14, 6, 58, 12, tzinfo=UTC)),
        ("2026-01-14 11:31:05", datetime(2026, 1, 14, 11, 31, 5, tzinfo=UTC)),
        ("2026-01-14T20:05:00", datetime(2026, 1, 14, 20, 5, tzinfo=UTC)),
        (None, None),
        ("", None),
        ("not a date", None),
        (True, None),
    ],
)
def test_parse_gmt(value: object, expected: datetime | None) -> None:
    assert parse_gmt(value) == expected

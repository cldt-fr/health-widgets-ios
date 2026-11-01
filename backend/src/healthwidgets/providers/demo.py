"""Synthetic provider: realistic, deterministic data for UI work, App Review and E2E tests.

Enabled with ``HW_ENABLE_DEMO_PROVIDER=true``. Values are seeded by calendar day, so a
given day always looks the same, and "today" fills in progressively as time passes.
"""

from __future__ import annotations

import math
import random
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from ..schemas import (
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
    LoadFocus,
    LoadFocusPart,
    PlannedWorkout,
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
    SportTotal,
    StepsMetric,
    StressMetric,
    TrainingDay,
    TrainingReadinessMetric,
    TrainingStatusMetric,
    TrainingWeek,
)

DEMO_TZ = ZoneInfo("Europe/Paris")
STEP = timedelta(minutes=15)


class DemoProvider:
    def fetch_snapshot(self, day: date, *, force: bool = False) -> DashboardSnapshot:
        return build_demo_snapshot(day)


def _local(day: date, hour: float) -> datetime:
    return datetime.combine(day, time(0), DEMO_TZ) + timedelta(hours=hour)


def _epoch(value: datetime) -> int:
    return int(value.timestamp())


def build_demo_snapshot(day: date, now: datetime | None = None) -> DashboardSnapshot:
    rng = random.Random(day.toordinal())
    now = now or datetime.now(UTC)
    start = _local(day, 0)
    end = min(now.astimezone(DEMO_TZ), _local(day, 24))
    progress = max(0.0, min(1.0, (end - start) / timedelta(hours=24)))
    hours_elapsed = progress * 24
    workout_at = 18.25 + rng.uniform(-0.75, 0.5)

    # -- sleep (previous evening -> this morning) --------------------------------------
    bedtime = _local(day, -1 + rng.uniform(-0.6, 0.4))  # around 23:00 the day before
    wake = _local(day, 7 + rng.uniform(-0.4, 0.5))
    segments: list[SleepSegment] = []
    cursor = bedtime
    cycle = [SleepStage.light, SleepStage.deep, SleepStage.light, SleepStage.rem]
    index = 0
    while cursor < wake:
        stage = cycle[index % len(cycle)]
        if index > 2 and rng.random() < 0.12:
            stage = SleepStage.awake
        minutes = {
            SleepStage.light: rng.uniform(18, 38),
            SleepStage.deep: rng.uniform(15, 35) * (1.4 if index < 6 else 0.6),
            SleepStage.rem: rng.uniform(10, 25) * (0.7 if index < 6 else 1.5),
            SleepStage.awake: rng.uniform(2, 7),
        }[stage]
        seg_end = min(wake, cursor + timedelta(minutes=minutes))
        segments.append(SleepSegment(start=_epoch(cursor), end=_epoch(seg_end), stage=stage))
        cursor = seg_end
        index += 1

    def stage_total(stage: SleepStage) -> int:
        return sum(s.end - s.start for s in segments if s.stage == stage)

    asleep = sum(s.end - s.start for s in segments if s.stage != SleepStage.awake)
    sleep_score = int(min(97, max(48, 62 + (asleep - 6 * 3600) / 360 + rng.uniform(-6, 8))))
    sleep_history = [
        DailyValue(date=(day - timedelta(days=n)).isoformat(), value=rng.randint(58, 92))
        for n in range(6, 0, -1)
    ] + [DailyValue(date=day.isoformat(), value=sleep_score)]

    # -- intraday series ---------------------------------------------------------------
    hr_series: list[Point] = []
    bb_series: list[Point] = []
    stress_series: list[Point] = []
    battery = 34 + rng.uniform(-6, 6)
    wake_hour = (wake - start) / timedelta(hours=1)
    t = start
    while t <= end:
        hour = (t - start) / timedelta(hours=1)
        asleep_now = hour < wake_hour
        workout = workout_at <= hour < workout_at + 0.9
        if asleep_now:
            hr = 49 + 4 * math.sin(hour) + rng.uniform(-2, 2)
            battery = min(100, battery + rng.uniform(5.5, 8.5) / 4)
            stress = rng.uniform(5, 18)
        elif workout:
            hr = 148 + rng.uniform(-8, 12)
            battery = max(5, battery - rng.uniform(2.5, 4.0))
            stress = None  # Garmin doesn't score stress during activities
        else:
            hr = 66 + 10 * math.sin((hour - 9) / 3) + rng.uniform(-5, 9)
            battery = max(5, battery - rng.uniform(0.6, 1.4))
            stress = max(8, min(85, 32 + 18 * math.sin(hour / 2.3) + rng.uniform(-10, 14)))
        hr_series.append(Point(t=_epoch(t), v=round(hr)))
        bb_series.append(Point(t=_epoch(t), v=round(battery)))
        if stress is not None:
            stress_series.append(Point(t=_epoch(t), v=round(stress)))
        t += STEP

    bb_values = [p.v for p in bb_series] or [battery]
    stress_values = [p.v for p in stress_series] or [0]
    hr_values = [p.v for p in hr_series] or [55]
    awake_fraction = max(0.0, min(1.0, (hours_elapsed - wake_hour) / (22 - wake_hour)))
    did_workout = hours_elapsed > workout_at + 0.9

    # -- daily totals ------------------------------------------------------------------
    step_goal = 10000
    steps = int(rng.uniform(9500, 14500) * awake_fraction)
    steps_history = [
        DailyValue(
            date=(day - timedelta(days=n)).isoformat(),
            value=rng.randint(5200, 15800),
            goal=step_goal,
        )
        for n in range(6, 0, -1)
    ] + [DailyValue(date=day.isoformat(), value=steps, goal=step_goal)]
    active_kcal = int(steps * 0.045 + (620 if did_workout else 0))
    resting_kcal = int(1720 * progress)
    rhr = 47 + rng.randint(-2, 3)

    hrv_last = 58 + rng.randint(-7, 6)
    activity = None
    if did_workout:
        distance = 10000 + rng.uniform(-2500, 2500)
        pace = 300 + rng.uniform(-15, 20)  # seconds per km
        activity = Activity(
            id=day.toordinal(),
            name="Course à pied",
            type="running",
            started_at=_local(day, workout_at),
            duration_seconds=distance / 1000 * pace + 40,
            moving_seconds=distance / 1000 * pace,
            distance_meters=distance,
            calories=620,
            average_hr=151,
            max_hr=172,
            average_speed=1000 / pace,
            elevation_gain=rng.uniform(40, 160),
            aerobic_effect=round(rng.uniform(2.8, 4.2), 1),
            anaerobic_effect=round(rng.uniform(0.6, 2.2), 1),
            effect_label="TEMPO",
            training_load=round(rng.uniform(110, 190)),
            vo2_max=54,
        )
    previous = Activity(
        id=day.toordinal() - 1,
        name="Vélo",
        type="cycling",
        started_at=_local(day - timedelta(days=1), 17.5),
        duration_seconds=5400,
        moving_seconds=5200,
        distance_meters=42800,
        calories=980,
        average_hr=138,
        max_hr=166,
        average_speed=8.2,
        elevation_gain=520,
        aerobic_effect=3.1,
        anaerobic_effect=0.8,
        effect_label="AEROBIC_BASE",
        training_load=142,
        vo2_max=None,
    )
    recent = [a for a in (activity, previous) if a is not None]

    readiness = 82 - (8 if did_workout else 0) + rng.randint(-6, 6)
    # Recovery clock: restarts at the end of today's workout, else counts from waking up.
    recovery_measured = _local(day, workout_at + 0.9) if did_workout else wake
    recovery_minutes = 14 * 60 if did_workout else 150
    level = (
        "prime"
        if readiness >= 95
        else "high"
        if readiness >= 75
        else "moderate"
        if readiness >= 50
        else "low"
    )

    return DashboardSnapshot(
        calendar_date=day.isoformat(),
        generated_at=now.replace(microsecond=0),
        source=Source(
            provider=ProviderId.demo,
            device_name="Forerunner 965 (démo)",
            last_sync_at=(end - timedelta(minutes=rng.randint(2, 18))).astimezone(UTC),
        ),
        unit_system="metric",
        steps=StepsMetric(
            count=steps, goal=step_goal, distance_meters=steps * 0.78, history=steps_history
        ),
        calories=CaloriesMetric(
            total=active_kcal + resting_kcal, active=active_kcal, resting=resting_kcal, goal=2600
        ),
        floors=FloorsMetric(ascended=round(12 * awake_fraction), goal=10),
        heart_rate=HeartRateMetric(
            resting=rhr,
            min=int(min(hr_values)),
            max=int(max(hr_values)),
            resting_seven_day_avg=rhr + 1,
            latest=int(hr_values[-1]),
            series=hr_series,
            history=[
                DailyValue(
                    date=(day - timedelta(days=n)).isoformat(), value=rhr + rng.randint(-2, 3)
                )
                for n in range(6, -1, -1)
            ],
        ),
        body_battery=BodyBatteryMetric(
            current=int(bb_values[-1]),
            highest=int(max(bb_values)),
            lowest=int(min(bb_values)),
            charged=int(max(bb_values) - bb_values[0]) if bb_values else None,
            drained=int(max(bb_values) - bb_values[-1]) if bb_values else None,
            at_wake=int(max(bb_values)),
            series=bb_series,
        ),
        stress=StressMetric(
            average=int(sum(stress_values) / len(stress_values)),
            max=int(max(stress_values)),
            current=int(stress_values[-1]),
            qualifier="balanced",
            rest_seconds=int(8.5 * 3600 * min(1, hours_elapsed / 9)),
            low_seconds=int(5 * 3600 * awake_fraction),
            medium_seconds=int(2.2 * 3600 * awake_fraction),
            high_seconds=int(0.6 * 3600 * awake_fraction),
            series=stress_series,
        ),
        sleep=SleepMetric(
            calendar_date=day.isoformat(),
            score=sleep_score,
            quality="excellent"
            if sleep_score >= 90
            else "good"
            if sleep_score >= 80
            else "fair"
            if sleep_score >= 60
            else "poor",
            duration_seconds=asleep,
            deep_seconds=stage_total(SleepStage.deep),
            light_seconds=stage_total(SleepStage.light),
            rem_seconds=stage_total(SleepStage.rem),
            awake_seconds=stage_total(SleepStage.awake),
            start=bedtime.astimezone(UTC),
            end=wake.astimezone(UTC),
            need_seconds=8 * 3600,
            avg_overnight_hrv=hrv_last,
            resting_heart_rate=rhr,
            avg_respiration=14.2,
            avg_spo2=95,
            avg_stress=14,
            body_battery_change=int(max(bb_values) - bb_values[0]) if bb_values else None,
            stages=segments,
            history=sleep_history,
        ),
        hrv=HrvMetric(
            last_night_avg=hrv_last,
            last_night_high=hrv_last + 21,
            weekly_avg=56,
            status="balanced",
            feedback="HRV_BALANCED_6",
            baseline=HrvBaseline(low_upper=44, balanced_low=49, balanced_upper=65),
            history=[
                DailyValue(
                    date=(day - timedelta(days=n)).isoformat(), value=56 + rng.randint(-8, 8)
                )
                for n in range(6, 0, -1)
            ]
            + [DailyValue(date=day.isoformat(), value=hrv_last)],
        ),
        training_readiness=TrainingReadinessMetric(
            score=readiness,
            level=level,
            # Garmin sends enum-like keys; the app localizes them.
            feedback_short="WELL_RECOVERED",
            feedback_long="READY_FOR_ACTION",
            recovery_time_minutes=recovery_minutes,
            measured_at=recovery_measured.astimezone(UTC),
            recovery_until=(recovery_measured + timedelta(minutes=recovery_minutes)).astimezone(
                UTC
            ),
            factors=[
                ReadinessFactor(key="sleep", percent=88, feedback="good", value=sleep_score),
                ReadinessFactor(key="recovery_time", percent=72, feedback="good", value=2),
                ReadinessFactor(key="hrv", percent=80, feedback="good", value=hrv_last),
                ReadinessFactor(key="acute_load", percent=64, feedback="moderate", value=642),
                ReadinessFactor(key="sleep_history", percent=76, feedback="good"),
                ReadinessFactor(key="stress_history", percent=82, feedback="good"),
            ],
        ),
        training_status=TrainingStatusMetric(
            status="productive",
            feedback_phrase="PRODUCTIVE_6",
            vo2_max=54,
            vo2_max_cycling=56,
            acute_load=642,
            chronic_load=581,
            load_ratio=1.1,
            acwr_status="optimal",
            acwr_percent=46,
            optimal_load_min=465,
            optimal_load_max=872,
            load_focus=LoadFocus(
                aerobic_low=LoadFocusPart(value=612, target_min=430, target_max=780),
                aerobic_high=LoadFocusPart(value=338, target_min=360, target_max=620),
                anaerobic=LoadFocusPart(value=126, target_min=90, target_max=240),
                feedback="AEROBIC_HIGH_SHORTAGE",
            ),
        ),
        intensity_minutes=IntensityMinutesMetric(
            moderate=96 + (25 if did_workout else 0),
            vigorous=38 + (30 if did_workout else 0),
            week_total=96 + 2 * 38 + (85 if did_workout else 0),
            weekly_goal=150,
            today=55 if did_workout else 8,
        ),
        spo2=Spo2Metric(average=96, lowest=89, latest=97),
        respiration=RespirationMetric(waking_avg=15.1, sleep_avg=14.2, lowest=11, highest=22),
        last_activity=recent[0] if recent else None,
        recent_activities=recent,
        race_predictions=RacePredictions(
            five_k=21 * 60 + 34,
            ten_k=44 * 60 + 52,
            half_marathon=99 * 60 + 5,
            marathon=208 * 60 + 40,
        ),
        training_week=demo_week(day, did_workout),
        upcoming_workouts=demo_plan(day, did_workout),
    )


# A typical half-marathon block: (weekday, sport, minutes, km, load, name, intent)
_WEEK = [
    (1, "running", 52, 10.2, 118, "Endurance fondamentale", "AEROBIC_LOW_SHORTAGE_BASE"),
    (2, "strength_training", 45, 0, 38, "Renforcement", None),
    (3, "running", 48, 9.1, 162, "Fractionné 6 x 800 m", "ANAEROBIC_SPEED"),
    (5, "cycling", 105, 48.0, 151, "Vélo endurance", "AEROBIC_LOW_SHORTAGE_BASE"),
    (6, "running", 95, 18.0, 214, "Sortie longue", "LONG_WORKOUT"),
]


def demo_week(day: date, did_workout_today: bool) -> TrainingWeek:
    monday = day - timedelta(days=day.weekday())
    days = []
    sports: dict[str, SportTotal] = {}
    for offset in range(7):
        current = monday + timedelta(days=offset)
        entry = TrainingDay(date=current.isoformat())
        for weekday, sport, minutes, km, load, _, _ in _WEEK:
            done = current < day or (current == day and did_workout_today)
            if weekday == current.weekday() and done:
                entry.count += 1
                entry.duration_seconds += minutes * 60
                entry.distance_meters += km * 1000
                entry.training_load += load
                entry.sports.append(sport)
                total = sports.setdefault(sport, SportTotal(type=sport))
                total.count += 1
                total.duration_seconds += minutes * 60
                total.distance_meters += km * 1000
        days.append(entry)
    duration = sum(d.duration_seconds for d in days)
    return TrainingWeek(
        week_start=monday.isoformat(),
        days=days,
        count=sum(d.count for d in days),
        duration_seconds=duration,
        distance_meters=sum(d.distance_meters for d in days),
        training_load=sum(d.training_load for d in days),
        elevation_gain=round(duration / 3600 * 70),
        previous_week_count=5,
        previous_week_duration_seconds=5.6 * 3600,
        previous_week_training_load=640,
        hr_zone_seconds=[round(duration * share) for share in (0.18, 0.56, 0.14, 0.09, 0.03)]
        if duration
        else [],
        sports=sorted(sports.values(), key=lambda t: t.duration_seconds, reverse=True),
    )


def demo_plan(day: date, did_workout_today: bool) -> list[PlannedWorkout]:
    plan = []
    for offset in range(7):
        current = day + timedelta(days=offset)
        match = next((w for w in _WEEK if w[0] == current.weekday()), None)
        if match is None:
            plan.append(
                PlannedWorkout(
                    date=current.isoformat(),
                    name="Repos",
                    is_rest_day=True,
                    plan_name="Semi-marathon · Garmin Coach",
                )
            )
            continue
        _, sport, minutes, km, _, name, intent = match
        plan.append(
            PlannedWorkout(
                date=current.isoformat(),
                name=name,
                sport=sport,
                intent=intent,
                duration_seconds=minutes * 60,
                distance_meters=km * 1000 or None,
                plan_name="Semi-marathon · Garmin Coach",
                completed=offset == 0 and did_workout_today,
            )
        )
    return plan

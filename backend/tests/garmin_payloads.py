"""Synthetic raw Garmin payloads for one day (2026-01-14, Europe/Paris).

The values are made up, but the shapes mirror real Garmin Connect responses key for key,
including their quirks: ISO strings without a zone, "local" epoch ms, -1/-2 sentinels,
null heart-rate samples and descriptor arrays whose key names differ per endpoint. The
summary, sleep, stress, heart-rate and daily-steps shapes were checked against live
responses; the others follow python-garminconnect's typed models.
"""

from __future__ import annotations

from typing import Any

DAY = "2026-01-14"
MIDNIGHT_MS = 1768345200000  # 2026-01-13T23:00:00Z == local midnight (CET)
SLEEP_START_MS = 1768344730000  # 2026-01-13T22:52:10Z
SLEEP_END_MS = 1768373410000  # 2026-01-14T06:50:10Z


def summary(**overrides: Any) -> dict[str, Any]:
    data = {
        "userProfileId": 1,
        "calendarDate": DAY,
        "totalSteps": 9312,
        "dailyStepGoal": 10000,
        "totalDistanceMeters": 7420,
        "wellnessDistanceMeters": 7420,
        "floorsAscended": 12.83412,
        "userFloorsAscendedGoal": 10,
        "totalKilocalories": 2564.0,
        "activeKilocalories": 712.0,
        "bmrKilocalories": 1852.0,
        "netCalorieGoal": 2100,
        "moderateIntensityMinutes": 18,
        "vigorousIntensityMinutes": 11,
        "intensityMinutesGoal": 150,
        "restingHeartRate": 52,
        "minHeartRate": 47,
        "maxHeartRate": 163,
        "minAvgHeartRate": 48,
        "maxAvgHeartRate": 158,
        "lastSevenDaysAvgRestingHeartRate": 53,
        "averageStressLevel": 31,
        "maxStressLevel": 88,
        "stressQualifier": "BALANCED",
        "restStressDuration": 29880,
        "lowStressDuration": 12600,
        "mediumStressDuration": 9840,
        "highStressDuration": 4200,
        "bodyBatteryChargedValue": 61,
        "bodyBatteryDrainedValue": 70,
        "bodyBatteryHighestValue": 91,
        "bodyBatteryLowestValue": 21,
        "bodyBatteryMostRecentValue": 21,
        "bodyBatteryAtWakeTime": 91,
        "bodyBatteryDuringSleep": 61,
        "averageSpo2": 95.0,
        "lowestSpo2": 88,
        "latestSpo2": 97,
        "avgWakingRespirationValue": 15.0,
        "highestRespirationValue": 23.0,
        "lowestRespirationValue": 9.0,
        "lastSyncTimestampGMT": "2026-01-14T06:58:12.417",
        "burnedKilocalories": None,
        "consumedKilocalories": None,
    }
    data.update(overrides)
    return data


def sleep() -> dict[str, Any]:
    return {
        "dailySleepDTO": {
            "id": SLEEP_START_MS,
            "calendarDate": DAY,
            "sleepTimeSeconds": 27600,
            "napTimeSeconds": 0,
            "sleepStartTimestampGMT": SLEEP_START_MS,
            "sleepEndTimestampGMT": SLEEP_END_MS,
            "sleepStartTimestampLocal": SLEEP_START_MS + 3_600_000,
            "sleepEndTimestampLocal": SLEEP_END_MS + 3_600_000,
            "deepSleepSeconds": 6000,
            "lightSleepSeconds": 15360,
            "remSleepSeconds": 6240,
            "awakeSleepSeconds": 1080,
            "averageSpO2Value": 96.0,
            "lowestSpO2Value": 89,
            "averageRespirationValue": 14.0,
            "avgSleepStress": 18.0,
            "avgHeartRate": 55.0,
            "sleepScoreFeedback": "POSITIVE_LONG_AND_DEEP",
            "sleepScores": {
                "overall": {"value": 84, "qualifierKey": "GOOD"},
                "totalDuration": {"qualifierKey": "EXCELLENT", "optimalStart": 27000.0},
                "remPercentage": {"value": 23, "qualifierKey": "GOOD"},
            },
            "sleepNeed": {"calendarDate": DAY, "baseline": 470, "actual": 470},
        },
        "sleepLevels": [
            {
                "startGMT": "2026-01-13T22:52:10.0",
                "endGMT": "2026-01-13T22:55:10.0",
                "activityLevel": 1.0,
            },
            {
                "startGMT": "2026-01-13T22:55:10.0",
                "endGMT": "2026-01-13T23:31:10.0",
                "activityLevel": 0.0,
            },
            {
                "startGMT": "2026-01-13T23:31:10.0",
                "endGMT": "2026-01-13T23:33:10.0",
                "activityLevel": 3.0,
            },
            {
                "startGMT": "2026-01-13T23:33:10.0",
                "endGMT": "2026-01-14T00:40:00.0",
                "activityLevel": 1.0,
            },
            {
                "startGMT": "2026-01-14T00:40:00.0",
                "endGMT": "2026-01-14T01:15:00.0",
                "activityLevel": 1.0,
            },
            {
                "startGMT": "2026-01-14T01:15:00.0",
                "endGMT": "2026-01-14T01:48:00.0",
                "activityLevel": 2.0,
            },
            {
                "startGMT": "2026-01-14T01:48:00.0",
                "endGMT": "2026-01-14T06:50:10.0",
                "activityLevel": 1.0,
            },
        ],
        "sleepMovement": [
            {
                "startGMT": "2026-01-13T21:52:00.0",
                "endGMT": "2026-01-13T21:53:00.0",
                "activityLevel": 4.1,
            }
        ],
        "hrvData": [
            {"value": 58.0, "startGMT": SLEEP_START_MS + 180_000},
            {"value": 63.0, "startGMT": SLEEP_START_MS + 480_000},
            {"value": 66.0, "startGMT": SLEEP_START_MS + 780_000},
        ],
        "sleepStress": [{"value": -1, "startGMT": SLEEP_START_MS + 5 * 3_600_000}],
        "avgOvernightHrv": 62.0,
        "hrvStatus": "BALANCED",
        "restingHeartRate": 52,
        "bodyBatteryChange": 61,
        "restlessMomentsCount": 24,
    }


def stress() -> dict[str, Any]:
    step = 180_000
    stress_values = [
        [MIDNIGHT_MS, 16],
        [MIDNIGHT_MS + step, 19],
        [MIDNIGHT_MS + 2 * step, -1],
        [MIDNIGHT_MS + 3 * step, -2],
        [MIDNIGHT_MS + 4 * step, 22],
        [MIDNIGHT_MS + 20 * step, 37],
    ]
    battery = [
        [MIDNIGHT_MS, "MEASURED", 34, 3.0],
        [MIDNIGHT_MS + step, "MEASURED", 34, 3.0],
        [MIDNIGHT_MS + 2 * step, "MEASURED", 35, 3.0],
        [MIDNIGHT_MS + 20 * step, "MEASURED", 21, 3.0],
    ]
    return {
        "calendarDate": DAY,
        "startTimestampGMT": "2026-01-13T23:00:00.0",
        "avgStressLevel": 31,
        "maxStressLevel": 88,
        "stressValueDescriptorsDTOList": [
            {"index": 0, "key": "timestamp"},
            {"index": 1, "key": "stressLevel"},
        ],
        "stressValuesArray": stress_values,
        "bodyBatteryValueDescriptorsDTOList": [
            {"bodyBatteryValueDescriptorIndex": 0, "bodyBatteryValueDescriptorKey": "timestamp"},
            {
                "bodyBatteryValueDescriptorIndex": 1,
                "bodyBatteryValueDescriptorKey": "bodyBatteryStatus",
            },
            {
                "bodyBatteryValueDescriptorIndex": 2,
                "bodyBatteryValueDescriptorKey": "bodyBatteryLevel",
            },
            {
                "bodyBatteryValueDescriptorIndex": 3,
                "bodyBatteryValueDescriptorKey": "bodyBatteryVersion",
            },
        ],
        "bodyBatteryValuesArray": battery,
    }


def heart_rates() -> dict[str, Any]:
    return {
        "calendarDate": DAY,
        "maxHeartRate": 158,
        "minHeartRate": 48,
        "restingHeartRate": 52,
        "lastSevenDaysAvgRestingHeartRate": 53,
        "heartRateValueDescriptors": [
            {"index": 0, "key": "timestamp"},
            {"index": 1, "key": "heartrate"},
        ],
        "heartRateValues": [
            [MIDNIGHT_MS, 61],
            [MIDNIGHT_MS + 120_000, 59],
            [MIDNIGHT_MS + 240_000, None],
            [MIDNIGHT_MS + 360_000, 60],
            [MIDNIGHT_MS + 3_600_000, 66],
        ],
    }


def daily_steps() -> list[dict[str, Any]]:
    rows = [
        ("2026-01-08", 10412, 8210),
        ("2026-01-09", 6120, 4870),
        ("2026-01-10", 13550, 10930),
        ("2026-01-11", 4980, 3960),
        ("2026-01-12", 11230, 9020),
        ("2026-01-13", 8760, 6990),
        ("2026-01-14", 9100, 7420),
    ]
    return [
        {"calendarDate": d, "totalSteps": s, "totalDistance": m, "stepGoal": 10000}
        for d, s, m in rows
    ]


def readiness() -> list[dict[str, Any]]:
    base = {
        "calendarDate": DAY,
        "level": "HIGH",
        "feedbackLong": "RECOVERED_AND_READY",
        "feedbackShort": "WELL_RECOVERED",
        "sleepScore": 84,
        "sleepScoreFactorPercent": 86,
        "sleepScoreFactorFeedback": "GOOD",
        "recoveryTime": 0,
        "recoveryTimeFactorPercent": 97,
        "recoveryTimeFactorFeedback": "GOOD",
        "acwrFactorPercent": 95,
        "acwrFactorFeedback": "VERY_GOOD",
        "acuteLoad": 412,
        "hrvFactorPercent": 90,
        "hrvFactorFeedback": "GOOD",
        "hrvWeeklyAverage": 60,
        "stressHistoryFactorPercent": 74,
        "stressHistoryFactorFeedback": "GOOD",
        "sleepHistoryFactorPercent": 71,
        "sleepHistoryFactorFeedback": "GOOD",
    }
    return [
        # newest first, like Garmin
        {
            **base,
            "timestamp": "2026-01-14T19:42:10.0",
            "score": 88,
            "inputContext": "UPDATE_REALTIME_VARIABLES",
            "recoveryTime": 412,
        },
        {
            **base,
            "timestamp": "2026-01-14T06:51:30.0",
            "score": 96,
            "level": "PRIME",
            "inputContext": "AFTER_WAKEUP_RESET",
        },
        {
            **base,
            "timestamp": "2026-01-13T23:40:02.0",
            "score": 83,
            "sleepScoreFactorPercent": 0,
            "sleepScoreFactorFeedback": "NONE",
            "inputContext": "UPDATE_REALTIME_VARIABLES",
        },
    ]


def hrv() -> dict[str, Any]:
    return {
        "hrvSummary": {
            "calendarDate": DAY,
            "weeklyAvg": 60,
            "lastNightAvg": 62,
            "lastNight5MinHigh": 88,
            "status": "BALANCED",
            "feedbackPhrase": "HRV_BALANCED_4",
            "baseline": {
                "lowUpper": 52,
                "balancedLow": 57,
                "balancedUpper": 71,
                "markerValue": 0.5,
            },
        },
        "hrvReadings": [{"hrvValue": 58, "readingTimeGMT": "2026-01-13T22:55:10.0"}],
    }


def training_status() -> dict[str, Any]:
    return {
        "mostRecentVO2Max": {
            "generic": {"calendarDate": DAY, "vo2MaxValue": 51.0, "vo2MaxPreciseValue": 51.3},
            "cycling": None,
        },
        "mostRecentTrainingStatus": {
            "latestTrainingStatusData": {
                "1000000001": {
                    "trainingStatus": 7,
                    "trainingStatusFeedbackPhrase": "PRODUCTIVE_3",
                    "primaryTrainingDevice": False,
                    "acuteTrainingLoadDTO": {"dailyTrainingLoadAcute": 10},
                },
                "1000000002": {
                    "trainingStatus": 7,
                    "trainingStatusFeedbackPhrase": "PRODUCTIVE_3",
                    "primaryTrainingDevice": True,
                    "acuteTrainingLoadDTO": {
                        "dailyTrainingLoadAcute": 412,
                        "dailyTrainingLoadChronic": 388,
                        "dailyAcuteChronicWorkloadRatio": 1.1,
                        "acwrStatus": "OPTIMAL",
                        "acwrPercent": 41,
                        "minTrainingLoadChronic": 310.4,
                        "maxTrainingLoadChronic": 582.0,
                    },
                },
            }
        },
        "mostRecentTrainingLoadBalance": {
            "metricsTrainingLoadBalanceDTOMap": {
                "1000000002": {
                    "primaryTrainingDevice": True,
                    "monthlyLoadAerobicLow": 512.3456,
                    "monthlyLoadAerobicHigh": 301.1,
                    "monthlyLoadAnaerobic": 98.7,
                    "monthlyLoadAerobicLowTargetMin": 380,
                    "monthlyLoadAerobicLowTargetMax": 690,
                    "monthlyLoadAerobicHighTargetMin": 330,
                    "monthlyLoadAerobicHighTargetMax": 560,
                    "monthlyLoadAnaerobicTargetMin": 80,
                    "monthlyLoadAnaerobicTargetMax": 210,
                    "trainingBalanceFeedbackPhrase": "AEROBIC_HIGH_SHORTAGE",
                }
            }
        },
    }


def intensity_week() -> list[dict[str, Any]]:
    return [
        {"calendarDate": "2026-01-12", "weeklyGoal": 150, "moderateValue": 84, "vigorousValue": 31}
    ]


def activities() -> list[dict[str, Any]]:
    return [
        {
            "activityId": 10000000002,
            "activityName": "Strength",
            "startTimeLocal": "2026-01-14 12:31:05",
            "startTimeGMT": "2026-01-14 11:31:05",
            "activityType": {"typeId": 13, "typeKey": "strength_training"},
            "distance": 0.0,
            "duration": 2711.402587890625,
            "movingDuration": 902.1150512695312,
            "calories": 356.0,
            "averageHR": 118.0,
            "maxHR": 151.0,
            "aerobicTrainingEffect": 1.9,
            "anaerobicTrainingEffect": 1.2,
            "trainingEffectLabel": "ANAEROBIC_CAPACITY",
            "activityTrainingLoad": 38.6,
        },
        {
            "activityId": 10000000001,
            "activityName": "Running",
            "startTimeLocal": "2026-01-12 18:20:44",
            "startTimeGMT": "2026-01-12 17:20:44",
            "activityType": {"typeId": 1, "typeKey": "running"},
            "distance": 8412.3,
            "duration": 2588.6,
            "movingDuration": 2561.0,
            "elevationGain": 64.0,
            "averageSpeed": 3.285,
            "averageHR": 149.0,
            "maxHR": 168.0,
            "calories": 598.0,
            "aerobicTrainingEffect": 3.4,
            "anaerobicTrainingEffect": 0.6,
            "trainingEffectLabel": "TEMPO",
            "activityTrainingLoad": 132.8,
            "vO2MaxValue": 51.0,
        },
    ]


def race_predictions() -> dict[str, Any]:
    return {
        "calendarDate": DAY,
        "time5K": 1395,
        "time10K": 2915,
        "timeHalfMarathon": 6480,
        "timeMarathon": 13690,
    }


def device() -> dict[str, Any]:
    return {
        "userDeviceId": 1000000002,
        "lastUsedDeviceName": "Forerunner 965",
        "lastUsedDeviceUploadTime": 1768373892000,
        "imageUrl": "https://example.com/forerunner-965.png",
    }


def sleep_history() -> list[dict[str, Any]]:
    return [
        {"calendarDate": "2026-01-12", "values": {"sleepScore": 79, "avgOvernightHrv": 59.0}},
        {"calendarDate": "2026-01-13", "values": {"sleepScore": 81, "avgOvernightHrv": 61.0}},
        {"calendarDate": "2026-01-14", "values": {"sleepScore": 83, "avgOvernightHrv": 62.0}},
    ]


def rhr_history() -> list[dict[str, Any]]:
    return [
        {"calendarDate": "2026-01-12", "value": 53},
        {"calendarDate": "2026-01-13", "value": 51},
        {"calendarDate": "2026-01-14", "value": 52},
    ]


def week_activities() -> list[dict[str, Any]]:
    """``get_activities_by_date`` from the previous Monday, newest first."""

    def item(aid, local, sport, duration, distance, load, elevation=None):
        return {
            "activityId": aid,
            "startTimeLocal": local,
            "activityType": {"typeKey": sport},
            "duration": duration,
            "distance": distance,
            "activityTrainingLoad": load,
            "elevationGain": elevation,
        }

    return [
        item(10000000002, "2026-01-14 12:31:05", "strength_training", 2711.4, 0.0, 38.6),
        item(10000000003, "2026-01-13 07:05:00", "cycling", 3600.0, 30500.0, 95.0, 210.0),
        item(10000000001, "2026-01-12 18:20:44", "running", 2588.6, 8412.3, 132.8, 64.0),
        item(10000000000, "2026-01-10 09:00:00", "running", 5400.0, 16000.0, 180.0),
        item(9999999999, "2026-01-03 09:00:00", "running", 3000.0, 9000.0, 90.0),
    ]


def hr_zones() -> dict[int, Any]:
    """``get_activity_hr_in_timezones`` per activity (the strength session has none)."""

    def zones(*seconds):
        return [
            {"zoneNumber": i + 1, "secsInZone": s, "zoneLowBoundary": 110 + 12 * i}
            for i, s in enumerate(seconds)
        ]

    return {
        10000000001: zones(300.0, 1500.0, 600.0, 150.0, 38.6),
        10000000003: zones(600.0, 2700.0, 300.0, 0.0, 0.0),
    }


def schedule() -> dict[str, Any]:
    """GraphQL ``workoutScheduleSummariesScalar`` (today -> +6 days)."""
    return {
        "data": {
            "workoutScheduleSummariesScalar": [
                {"scheduleDate": "2026-01-13", "workoutId": 110, "workoutName": "Yesterday"},
                {
                    "scheduleDate": "2026-01-14",
                    "workoutUuid": "u-1",
                    "workoutId": 111,
                    "workoutName": "Tempo 3x10",
                    "workoutType": "running",
                    "estimatedDurationInSecs": 3300,
                    "estimatedDistanceInMeters": 9500.0,
                    "associatedActivityId": None,
                },
                {
                    "scheduleDate": "2026-01-16",
                    "workoutId": 112,
                    "workoutName": "Strength A",
                    "workoutType": "strength_training",
                    "estimatedDurationInSecs": 2400,
                },
            ]
        }
    }


def training_plan() -> dict[str, Any]:
    """GraphQL ``trainingPlanScalar`` (Garmin Coach), same item shape."""
    return {
        "data": {
            "trainingPlanScalar": {
                "trainingPlanWorkoutScheduleDTOS": [
                    {
                        "planName": "Half Marathon",
                        "workoutScheduleSummaries": [
                            {
                                "scheduleDate": "2026-01-14",
                                "workoutUuid": "u-1",
                                "workoutName": "Tempo 3x10",
                                "workoutType": "running",
                            },
                            {
                                "scheduleDate": "2026-01-15",
                                "workoutUuid": "u-2",
                                "workoutName": "Base",
                                "workoutType": "RUNNING",
                                "workoutPhrase": "AEROBIC_LOW_SHORTAGE_BASE",
                                "estimatedDurationInSecs": 2700,
                            },
                            {"scheduleDate": "2026-01-17", "isRestDay": True},
                            {
                                "scheduleDate": "2026-01-18",
                                "workoutUuid": "u-3",
                                "workoutName": "Half marathon",
                                "workoutType": "running",
                                "race": True,
                                "estimatedDistanceInMeters": 21097.5,
                                "associatedActivityId": None,
                            },
                        ],
                    }
                ]
            }
        }
    }


def bundle() -> dict[str, Any]:
    """Everything ``fetch_raw`` collects for one day, keyed by endpoint name."""
    return {
        "summary": summary(),
        "sleep": sleep(),
        "stress": stress(),
        "heart_rates": heart_rates(),
        "steps_history": daily_steps(),
        "readiness": readiness(),
        "hrv": hrv(),
        "training_status": training_status(),
        "intensity_week": intensity_week(),
        "activities": activities(),
        "race_predictions": race_predictions(),
        "device": device(),
        "sleep_history": sleep_history(),
        "rhr_history": rhr_history(),
        "hrv_history": None,
        "week_activities": week_activities(),
        "schedule": schedule(),
        "training_plan": training_plan(),
    }

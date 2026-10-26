"""Hand-written expectations for the reference implementations.
These are independent of the generated vectors: they pin the rules from the docs with values worked out by hand.
Run: python3 -m unittest discover -s tools/reference
"""
import unittest
from datetime import date, datetime, timezone

from pushly_ref import account, clan_war, ranking
from pushly_ref.occurrences import all_occurrences, challenge_occurrence, occurrences
from pushly_ref.plan import android_next, ios_plan, os_alarm_id
from pushly_ref.validation import validate_schedule


def utc(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def weekly(id_="a1", times=None, **kw):
    s = {"id": id_, "enabled": True, "countsForChallenge": True, "kind": "weekly",
         "weekly": times or {d: "06:30" for d in ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]},
         "overrides": [], "pause": None, "mode": {"type": "ringUntilDone", "targetReps": 20}}
    s.update(kw)
    return s


class Occurrences(unittest.TestCase):
    def test_per_weekday_times(self):
        s = weekly(times={"mon": "06:30", "tue": "07:15", "wed": None, "thu": "06:30", "fri": "06:30",
                          "sat": "09:00", "sun": None})
        # Monday 2026-10-19 00:00 Prague (= 2026-10-18 22:00Z), horizon 6 → Mon..Sun
        occ = occurrences(s, utc("2026-10-18T22:00:00Z"), "Europe/Prague", 6)
        self.assertEqual([o.local_date.isoformat() for o in occ],
                         ["2026-10-19", "2026-10-20", "2026-10-22", "2026-10-23", "2026-10-24"])
        self.assertEqual(occ[1].instant, utc("2026-10-20T05:15:00Z"))   # 07:15 CEST
        self.assertEqual(occ[4].instant, utc("2026-10-24T07:00:00Z"))   # Sat 09:00 CEST

    def test_spring_forward_gap_rings_at_first_valid_minute(self):
        s = weekly(times={"sun": "02:30"})
        occ = occurrences(s, utc("2027-03-27T12:00:00Z"), "Europe/Prague", 1)
        self.assertEqual(len(occ), 1)
        self.assertEqual(occ[0].instant, utc("2027-03-28T01:00:00Z"))   # 03:00 CEST

    def test_fall_back_overlap_rings_first_instance(self):
        s = weekly(times={"sun": "02:30"})
        occ = occurrences(s, utc("2026-10-24T12:00:00Z"), "Europe/Prague", 1)
        self.assertEqual(occ[0].instant, utc("2026-10-25T00:30:00Z"))   # first 02:30 is still CEST (+2)

    def test_override_skip_and_pause(self):
        s = weekly(overrides=[{"date": "2026-10-21", "time": "05:40"}, {"date": "2026-10-22", "skip": True}],
                   pause={"from": "2026-10-24", "to": "2026-10-25"})
        occ = occurrences(s, utc("2026-10-19T12:00:00Z"), "Europe/Prague", 6)
        dates = [o.local_date.isoformat() for o in occ]
        self.assertEqual(dates, ["2026-10-20", "2026-10-21", "2026-10-23"])
        self.assertEqual(occ[1].instant, utc("2026-10-21T03:40:00Z"))

    def test_past_occurrence_today_is_dropped(self):
        s = weekly()
        occ = occurrences(s, utc("2026-10-19T05:00:00Z"), "Europe/Prague", 0)   # 07:00 local, alarm was 06:30
        self.assertEqual(occ, [])

    def test_half_hour_zone(self):
        s = weekly()
        occ = occurrences(s, utc("2026-10-18T00:00:00Z"), "Asia/Kolkata", 0)
        self.assertEqual(occ[0].instant, utc("2026-10-18T01:00:00Z"))   # 06:30 IST = 01:00Z

    def test_disabled_alarm(self):
        self.assertEqual(occurrences(weekly(enabled=False), utc("2026-10-18T00:00:00Z"), "UTC", 7), [])

    def test_challenge_occurrence_earliest_counting_alarm(self):
        a = weekly("a", times={"mon": "07:00"})
        b = weekly("b", times={"mon": "06:00"}, countsForChallenge=False)
        c = weekly("c", times={"mon": "06:45"})
        occ = all_occurrences([a, b, c], utc("2026-10-18T12:00:00Z"), "Europe/Prague", 1)
        ch = challenge_occurrence(date(2026, 10, 19), occ)
        self.assertEqual(ch.alarm_id, "c")


class Validation(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate_schedule(weekly(), date(2026, 10, 19)), [])

    def test_bounds(self):
        s = weekly(mode={"type": "sprint", "windowSeconds": 45, "minimumReps": 3})
        self.assertEqual(set(validate_schedule(s, date(2026, 10, 19))), {"mode.windowSeconds", "mode.minimumReps"})
        s = weekly(pause={"from": "2026-11-01", "to": "2026-12-15"})
        self.assertIn("pause.tooLong", validate_schedule(s, date(2026, 10, 19)))


class Trophies(unittest.TestCase):
    def test_truncating_division(self):
        self.assertEqual(ranking.tdiv(-49, 25), -1)
        self.assertEqual(ranking.tdiv(49, 25), 1)

    def test_equal_trophies(self):
        self.assertEqual(ranking.win_gain(1000, 1000), 30)
        self.assertEqual(ranking.loss_cost(1000, 1000), 20)

    def test_underdog_and_clamps(self):
        self.assertEqual(ranking.win_gain(1000, 1500), 50)   # 30 + 20 = 50
        self.assertEqual(ranking.loss_cost(1000, 1500), 5)   # 20 - 20 = 0 -> clamp 5
        self.assertEqual(ranking.win_gain(1500, 1000), 10)   # 30 - 20 = 10
        self.assertEqual(ranking.loss_cost(1500, 1000), 40)  # 20 + 20 = 40
        self.assertEqual(ranking.win_gain(1000, 1049), 31)

    def test_placement_and_streak(self):
        s = ranking.TrophyState(trophies=0, placement_left=5, win_streak=2)
        s2, d = ranking.apply_ranked_result(s, 0, "win")
        self.assertEqual(d, 30 * 3 // 2 + 3)                 # 45 + streak bonus 3
        s3, d = ranking.apply_ranked_result(ranking.TrophyState(trophies=100, placement_left=1), 100, "loss")
        self.assertEqual(d, -10)

    def test_floor(self):
        s = ranking.TrophyState(trophies=610, floor=600, placement_left=0)
        s2, d = ranking.apply_ranked_result(s, 610, "loss")
        self.assertEqual((s2.trophies, d), (600, -10))
        s3, _ = ranking.apply_ranked_result(ranking.TrophyState(trophies=590, placement_left=0), 590, "win")
        self.assertEqual(s3.floor, 600)

    def test_never_negative(self):
        s2, d = ranking.apply_ranked_result(ranking.TrophyState(trophies=7, placement_left=0), 7, "loss")
        self.assertEqual(s2.trophies, 0)
        self.assertEqual(d, -7)

    def test_leagues(self):
        self.assertEqual(ranking.league_for(0), {"league": "bronze", "tier": "III"})
        self.assertEqual(ranking.league_for(1465), {"league": "gold", "tier": "III"})
        self.assertEqual(ranking.league_for(1466), {"league": "gold", "tier": "II"})
        self.assertEqual(ranking.league_for(1732), {"league": "gold", "tier": "I"})
        self.assertEqual(ranking.league_for(4500), {"league": "champion", "tier": None})
        self.assertEqual(ranking.league_for(5000), {"league": "legend", "tier": None})

    def test_season_reset(self):
        self.assertEqual(ranking.season_reset(1900), 1900)
        self.assertEqual(ranking.season_reset(3001), 2500)

    def test_wake_points(self):
        self.assertEqual(ranking.wake_points("ringUntilDone", 20, 80), 10 + 4 + 0 + 1)
        self.assertEqual(ranking.wake_points("beatTheClock", 100, 95), 10 + 20 + 3 + 3)
        self.assertEqual(ranking.wake_points("escalation", 5, 50, snoozes_used=3), 5)   # 10+1-6 = 5


class ClanWar(unittest.TestCase):
    def test_caps(self):
        self.assertEqual(clan_war.counted_total(150), 150)
        self.assertEqual(clan_war.counted_total(300), 250)
        self.assertEqual(clan_war.counted_total(1000), 300)
        self.assertEqual(clan_war.counted_total(301), 250)   # 201..301 -> 101 // 2 = 50

    def test_split_independence(self):
        one = clan_war.counted_for_session(0, 333)
        parts = sum(clan_war.counted_for_session(b, n) for b, n in [(0, 100), (100, 150), (250, 83)])
        self.assertEqual(one, parts)

    def test_low_trust(self):
        self.assertEqual(clan_war.counted_total(300, low_trust=True), 125)


class Account(unittest.TestCase):
    def test_usernames(self):
        self.assertIsNone(account.username_error("AnaFit"))
        self.assertEqual(account.username_error("ab"), "tooShort")
        self.assertEqual(account.username_error("a" * 21), "tooLong")
        self.assertEqual(account.username_error("ana fit"), "invalidCharacters")
        self.assertEqual(account.username_error("u_0123456789ab"), "reserved")
        self.assertIsNone(account.username_error("u_0123456789AB"))   # server placeholder regex is lowercase hex only

    def test_age_gate_by_birth_year(self):
        self.assertIsNone(account.birth_year_error(2010, 2026))        # turns 16 this year -> allowed
        self.assertEqual(account.birth_year_error(2011, 2026), "tooYoung")
        self.assertEqual(account.birth_year_error(1899, 2026), "invalid")

    def test_versions(self):
        self.assertTrue(account.update_required("1.2", "1.10"))
        self.assertFalse(account.update_required("1.10.0", "1.9.9"))
        self.assertFalse(account.update_required("1.0.0", "1"))


class Plan(unittest.TestCase):
    def test_challenge_occurrence_gets_three_nags_two_minutes_apart(self):
        s = weekly(times={"tue": "06:30"})
        plan = ios_plan([s], utc("2026-10-19T12:00:00Z"), "Europe/Prague", 1, 3)
        self.assertEqual([(e["role"], e["fireAt"]) for e in plan],
                         [("main", "2026-10-20T04:30:00Z"), ("nag1", "2026-10-20T04:32:00Z"),
                          ("nag2", "2026-10-20T04:34:00Z"), ("nag3", "2026-10-20T04:36:00Z")])

    def test_non_challenge_alarm_has_no_nags(self):
        s = weekly(times={"tue": "06:30"}, countsForChallenge=False)
        plan = ios_plan([s], utc("2026-10-19T12:00:00Z"), "Europe/Prague", 1, 3)
        self.assertEqual([e["role"] for e in plan], ["main"])

    def test_nags_stop_before_deadline(self):
        s = weekly(times={"tue": "06:30"})
        plan = ios_plan([s], utc("2026-10-19T12:00:00Z"), "Europe/Prague", 1, 20)
        self.assertEqual(plan[-1]["role"], "nag14")   # +28 min; +30 would hit the deadline

    def test_ids_are_deterministic_uuid5(self):
        self.assertEqual(os_alarm_id("x:2026-10-19", "main"), os_alarm_id("x:2026-10-19", "main"))
        self.assertNotEqual(os_alarm_id("x:2026-10-19", "main"), os_alarm_id("x:2026-10-19", "nag1"))
        self.assertEqual(os_alarm_id("x:2026-10-19", "main")[14], "5")

    def test_android_next_finds_one_off_far_ahead(self):
        s = weekly(kind="oneOff", oneOff="2027-02-01T07:00")
        s.pop("weekly")
        nxt = android_next([s], utc("2026-10-19T12:00:00Z"), "Europe/Prague")
        self.assertEqual(nxt["a1"], {"occurrenceId": "a1:2027-02-01", "fireAt": "2027-02-01T06:00:00Z"})


if __name__ == "__main__":
    unittest.main()


class RepEngineReference(unittest.TestCase):
    """doc 05 §4–5. Scenario labels are written as a coach would label them; the engine must agree."""

    def test_angle(self):
        from pushly_ref.rep_engine import angle
        self.assertAlmostEqual(angle((1, 0), (0, 0), (0, 1)), 90.0)
        self.assertAlmostEqual(angle((1, 0, 0), (0, 0, 0), (-1, 0, 0)), 180.0)
        self.assertEqual(angle((0, 0), (0, 0), (1, 1)), 180.0)

    def test_reversals_ignore_small_wiggles(self):
        from pushly_ref.rep_engine import reversals
        self.assertEqual(reversals([150, 120, 90, 95, 120, 160], 8), 1)          # one clean down-up
        self.assertEqual(reversals([150, 120, 125, 100, 160], 8), 1)             # 5° wiggle ignored
        self.assertEqual(reversals([150, 110, 135, 85, 160], 8), 3)              # down-up-down-up

    def test_one_euro_converges(self):
        from pushly_ref.rep_engine import OneEuro
        f = OneEuro(1.2, 0.05, 1.0)
        values = [f(10.0 if i else 0.0, 1 / 30) for i in range(60)]
        self.assertEqual(values[0], 0.0)
        self.assertAlmostEqual(values[-1], 10.0, places=2)

    def test_every_synthetic_scenario_matches_its_label(self):
        from pushly_ref import pushup_scenarios, rep_engine
        for sid, vector in pushup_scenarios.build().items():
            result = rep_engine.run(vector)
            expected = vector["expected"]
            with self.subTest(sid):
                self.assertEqual(result["counted"], expected["counted"])
                if "rejected" in expected:
                    self.assertEqual(result["rejected"], expected["rejected"])
                if "cheat" in vector["meta"]["tags"]:
                    self.assertEqual(result["counted"], 0)


class Workouts(unittest.TestCase):
    def test_reps_set_ends_at_target_then_rests(self):
        from pushly_ref import workout as wk
        w = {"id": "x", "name": "x", "sets": [{"kind": "reps", "target": 2, "restS": 30}, {"kind": "reps", "target": 1, "restS": 0}]}
        r = wk.run(w, [{"op": "start", "t": 0}, {"op": "rep", "t": 1000}, {"op": "rep", "t": 2000}])
        self.assertEqual(r.phase, "rest")
        self.assertEqual(r.snapshot(2000)["msLeft"], 30000)
        r.rep(40000)  # rest is over at 32 s → set 2 starts, this rep completes it
        self.assertEqual(r.phase, "done")
        self.assertEqual([x["completed"] for x in r.results], [True, True])

    def test_emom_unfinished_set_rolls_over(self):
        from pushly_ref import workout as wk
        w = {"id": "x", "name": "x", "everyS": 30, "sets": [{"kind": "reps", "target": 5, "restS": 0}] * 2}
        r = wk.run(w, [{"op": "start", "t": 0}, {"op": "rep", "t": 1000}, {"op": "tick", "t": 30000}])
        self.assertEqual((r.phase, r.index), ("set", 1))
        self.assertFalse(r.results[0]["completed"])

    def test_presets_are_valid(self):
        import json
        from pathlib import Path
        from pushly_ref import workout as wk
        presets = json.loads((Path(__file__).resolve().parents[2] / "shared/workouts/presets.json").read_text())["presets"]
        self.assertGreaterEqual(len(presets), 6)
        for p in presets:
            self.assertEqual(wk.validate(p), [], p["id"])


class BattleRecapTest(unittest.TestCase):
    def test_close_calls(self):
        from pushly_ref.battle_recap import recap
        from pushly_ref.battle_recap_cases import BATTLES
        by_id = {b["id"]: recap(b) for b in BATTLES}
        self.assertEqual(by_id["lost-by-one"]["margin"], {"kind": "reps", "n": 1})
        self.assertTrue(by_id["lost-by-one"]["close"])
        self.assertEqual((by_id["won-by-five-as-b"]["mine"], by_id["won-by-five-as-b"]["theirs"]), (25, 20))
        self.assertFalse(by_id["won-by-five-as-b"]["close"])
        self.assertEqual(by_id["speed-photo-finish"]["margin"], {"kind": "time", "ms": 400})
        self.assertTrue(by_id["bo3-two-one"]["close"])
        self.assertEqual(by_id["i-left"]["margin"], {"kind": "forfeit", "byMe": True})
        self.assertEqual(by_id["void"]["margin"], {"kind": "void"})

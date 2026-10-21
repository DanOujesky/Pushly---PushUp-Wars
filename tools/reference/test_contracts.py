"""Every schedule in the shared vectors that the rules accept must also match the JSON Schema contract
(shared/contracts/alarm-schedule.schema.json), so clients, server and vectors agree on the wire shape."""
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads((ROOT / "shared/contracts/alarm-schedule.schema.json").read_text())
VALIDATOR = Draft202012Validator(SCHEMA)


def errors(doc: dict) -> list[str]:
    return [f"{'/'.join(map(str, e.path))}: {e.message}" for e in VALIDATOR.iter_errors(doc)]


class AlarmScheduleContract(unittest.TestCase):
    def test_schema_is_valid(self):
        Draft202012Validator.check_schema(SCHEMA)

    def test_occurrence_vector_schedules_match(self):
        for path in sorted((ROOT / "shared/test-vectors/alarm-occurrences").glob("*.json")):
            for s in json.loads(path.read_text())["schedules"]:
                self.assertEqual(errors(s), [], f"{path.name} / {s['id']}")

    def test_valid_validation_cases_match(self):
        cases = json.loads((ROOT / "shared/test-vectors/alarm-validation/cases.json").read_text())["cases"]
        for c in cases:
            if not c["expectedErrors"]:
                self.assertEqual(errors(c["schedule"]), [], c["id"])

    def test_rejects_unknown_fields_and_bad_times(self):
        cases = json.loads((ROOT / "shared/test-vectors/alarm-validation/cases.json").read_text())["cases"]
        base = dict(cases[0]["schedule"])
        self.assertNotEqual(errors({**base, "surprise": 1}), [])
        self.assertNotEqual(errors({**base, "weekly": {**base["weekly"], "mon": "6:30"}}), [])
        self.assertNotEqual(errors({**base, "mode": {"type": "dance"}}), [])


    def test_wake_vector_alarms_match(self):
        plans = json.loads((ROOT / "shared/test-vectors/wake/day-plans.json").read_text())["cases"]
        for c in plans:
            for alarm_id, versions in c["alarms"].items():
                for v in versions:
                    if v["data"] is not None:
                        self.assertEqual(errors(v["data"]), [], f"{c['id']} / {alarm_id} v{v['version']}")


CONTRACTS = ROOT / "shared/contracts"
# Example payloads exactly as the backend returns them; both apps decode the same files.
FIXTURE_SCHEMAS = {
    "submit_rep_session_response.json": "submit-rep-session.response.schema.json",
    "wake_summary.json": "wake-summary.schema.json",
    "stats.json": "stats.schema.json",
    "achievements.json": "achievements.schema.json",
    "leaderboard.json": "leaderboard.schema.json",
    "friends.json": "friends.schema.json",
    "friend_feed.json": "friend-feed.schema.json",
    "user_search.json": "user-search.schema.json",
}


class ResponseContracts(unittest.TestCase):
    def test_schemas_are_valid(self):
        for p in CONTRACTS.glob("*.schema.json"):
            with self.subTest(schema=p.name):
                Draft202012Validator.check_schema(json.loads(p.read_text()))

    def test_fixtures_match_schemas(self):
        schemas = {p.name: json.loads(p.read_text()) for p in CONTRACTS.glob("*.schema.json")}
        registry = Registry().with_resources([(s["$id"], Resource.from_contents(s)) for s in schemas.values()])
        for fixture, schema in FIXTURE_SCHEMAS.items():
            with self.subTest(fixture=fixture):
                Draft202012Validator(schemas[schema], registry=registry).validate(
                    json.loads((CONTRACTS / "fixtures" / fixture).read_text()))


if __name__ == "__main__":
    unittest.main()

"""Every schedule in the shared vectors that the rules accept must also match the JSON Schema contract
(shared/contracts/alarm-schedule.schema.json), so clients, server and vectors agree on the wire shape."""
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

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


if __name__ == "__main__":
    unittest.main()

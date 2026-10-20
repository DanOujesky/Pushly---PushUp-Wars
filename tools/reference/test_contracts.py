"""Contract fixtures must match their JSON Schemas (shared/contracts). Both apps decode the same fixtures."""
import json
import unittest
from pathlib import Path

import jsonschema
from referencing import Registry, Resource

CONTRACTS = Path(__file__).resolve().parents[2] / "shared/contracts"
FIXTURES = {
    "submit_rep_session_response.json": "submit-rep-session.response.schema.json",
    "wake_summary.json": "wake-summary.schema.json",
}


class ContractFixtures(unittest.TestCase):
    def test_fixtures_match_schemas(self):
        schemas = [json.loads(p.read_text()) for p in CONTRACTS.glob("*.schema.json")]
        registry = Registry().with_resources([(s["$id"], Resource.from_contents(s)) for s in schemas])
        by_name = {p.name: json.loads(p.read_text()) for p in CONTRACTS.glob("*.schema.json")}
        for fixture, schema in FIXTURES.items():
            with self.subTest(fixture=fixture):
                validator = jsonschema.Draft202012Validator(by_name[schema], registry=registry)
                validator.validate(json.loads((CONTRACTS / "fixtures" / fixture).read_text()))

    def test_schemas_are_valid(self):
        for p in CONTRACTS.glob("*.schema.json"):
            with self.subTest(schema=p.name):
                jsonschema.Draft202012Validator.check_schema(json.loads(p.read_text()))


if __name__ == "__main__":
    unittest.main()

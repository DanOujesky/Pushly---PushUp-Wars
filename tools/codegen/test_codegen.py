"""Tests for the code generator. Run: python3 -m unittest discover -s tools/codegen"""
import json
import unittest
from pathlib import Path

import generate
from check_contrast import check, contrast


class Naming(unittest.TestCase):
    def test_camel_cases(self):
        self.assertEqual(generate.lower_camel("bg.base"), "bgBase")
        self.assertEqual(generate.lower_camel("display.counter"), "displayCounter")
        self.assertEqual(generate.upper_camel("text.secondary"), "TextSecondary")
        self.assertEqual(generate.lower_camel("trackingLostMs"), "trackingLostMs")
        self.assertEqual(generate.upper_camel("oneEuro"), "OneEuro")

    def test_int_keys(self):
        self.assertEqual(generate.swift_value("minRepMs", 450), ("Int", "450"))
        self.assertEqual(generate.swift_value("topMinDeg", 155), ("Double", "155.0"))
        self.assertEqual(generate.swift_value("bottomMaxDeg", [90, 105]), ("ClosedRange<Double>", "90.0...105.0"))
        with self.assertRaises(ValueError):
            generate.swift_value("minRepMs", 450.5)


class Outputs(unittest.TestCase):
    def test_every_color_token_is_generated_on_both_platforms(self):
        files = generate.outputs()
        tokens = json.loads(generate.TOKENS.read_text())
        swift, kotlin = files[generate.IOS_TOKENS], files[generate.KT_TOKENS]
        for name in tokens["color"]:
            self.assertIn(f"static let {generate.lower_camel(name)} =", swift)
            self.assertIn(f"val {generate.upper_camel(name)} =", kotlin)

    def test_spec_constants_match_yaml(self):
        files = generate.outputs()
        swift = next(v for k, v in files.items() if k.name == "PushupSpecV1.swift")
        kotlin = next(v for k, v in files.items() if k.name == "PushupSpecV1.kt")
        self.assertIn("public static let bottomMaxDeg: Double = 100.0", swift)
        self.assertIn("const val BOTTOM_MAX_DEG: Double = 100.0", kotlin)
        self.assertIn("public static let minRepMs: Int = 450", swift)
        self.assertIn("const val MIN_REP_MS: Int = 450", kotlin)


class Contrast(unittest.TestCase):
    def test_black_white(self):
        self.assertAlmostEqual(contrast("#000000", "#FFFFFF"), 21.0, places=1)

    def test_tokens_pass(self):
        self.assertEqual(check(json.loads(generate.TOKENS.read_text())), [])


if __name__ == "__main__":
    unittest.main()

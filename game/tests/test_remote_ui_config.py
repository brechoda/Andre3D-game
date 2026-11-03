import json
import re
import unittest
from pathlib import Path


GAME_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = GAME_ROOT / "config" / "remote_ui.json"
SCRIPT_PATH = GAME_ROOT / "autoload" / "remote_ui_config.gd"
UPDATER_PATH = GAME_ROOT / "autoload" / "remote_updater.gd"


class RemoteUIConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        cls.script = SCRIPT_PATH.read_text(encoding="utf-8")

    def _constant_ids(self, constant_name):
        match = re.search(
            rf"const {re.escape(constant_name)} := \[(.*?)\]",
            self.script,
            flags=re.S,
        )
        self.assertIsNotNone(match, f"missing constant {constant_name}")
        return set(re.findall(r'"([^"]+)"', match.group(1)))

    def test_schema_and_element_keys_are_supported(self):
        self.assertEqual(self.config.get("schema_version"), 1)
        self.assertIsInstance(self.config.get("revision"), str)
        elements = self.config.get("elements")
        self.assertIsInstance(elements, dict)
        supported = self._constant_ids("ELEMENT_IDS")
        self.assertTrue(set(elements).issubset(supported))
        self.assertIn("menu.start_button", elements)
        self.assertIn("hud.gps", elements)
        self.assertIn("hud.microphone", supported)

    def test_values_are_bounded_and_json_only(self):
        elements = self.config["elements"]
        for element_id, settings in elements.items():
            self.assertIsInstance(settings, dict, element_id)
            self.assertFalse({"script", "path", "node_path", "method"} & set(settings))
            if "scale" in settings:
                self.assertGreaterEqual(settings["scale"], 0.5)
                self.assertLessEqual(settings["scale"], 2.0)
            if "font_size" in settings:
                self.assertGreaterEqual(settings["font_size"], 8)
                self.assertLessEqual(settings["font_size"], 72)
            for color_key in ("text_color", "background_color", "tint"):
                if color_key in settings:
                    self.assertRegex(settings[color_key], r"^#[0-9A-Fa-f]{6}$")
            for vector_key in ("position", "size", "min_size"):
                if vector_key in settings:
                    self.assertEqual(len(settings[vector_key]), 2)
                    self.assertTrue(all(isinstance(value, (int, float)) for value in settings[vector_key]))

    def test_required_gameplay_controls_cannot_be_remote_hidden(self):
        visibility = self._constant_ids("VISIBILITY_IDS")
        self.assertNotIn("menu.start_button", visibility)
        self.assertNotIn("menu.panel", visibility)
        self.assertNotIn("hud.moto.accelerate", visibility)
        self.assertNotIn("hud.hilux.accelerate", visibility)
        self.assertIn('element_id == "menu.start_button" or not raw.has(key)', self.script)
        self.assertIn('element_id != "menu.start_button"', self.script)

    def test_runtime_pck_does_not_override_apk_code(self):
        updater = UPDATER_PATH.read_text(encoding="utf-8")
        self.assertIn("ProjectSettings.load_resource_pack(package_path, false)", updater)


if __name__ == "__main__":
    unittest.main()

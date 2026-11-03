from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PERMISSION = "android.permission.POST_NOTIFICATIONS"


class AndroidNotificationPermissionTests(unittest.TestCase):
    def test_permission_is_declared_for_android_export(self):
        manifest = ROOT.parent / "android_plugin_src" / "AndroidManifest.xml"
        android_name = "{http://schemas.android.com/apk/res/android}name"
        declared = {
            node.attrib.get(android_name)
            for node in ET.parse(manifest).getroot().findall("uses-permission")
        }
        self.assertIn(PERMISSION, declared)

        export_preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        self.assertIn(PERMISSION, export_preset)

    def test_only_android_startup_requests_the_single_notification_permission(self):
        menu = (ROOT / "scripts" / "session_menu.gd").read_text(encoding="utf-8")
        gate = menu.index("if not RemoteUpdater.is_client_update_required():")
        prompt = menu.index('call_deferred("_request_notification_permission")', gate)
        map_download = menu.index('call_deferred("_prepare_selected_map")', gate)
        self.assertLess(gate, prompt)
        self.assertLess(prompt, map_download)

        start = menu.index("func _request_notification_permission() -> void:")
        end = menu.find("\nfunc ", start + 1)
        method = menu[start:end if end >= 0 else None]
        self.assertIn('OS.has_feature("android")', method)
        self.assertIn(PERMISSION, method)
        self.assertIn("OS.request_permission(permission)", method)
        self.assertNotIn("OS.request_permissions()", method)
        self.assertNotIn("RECORD_AUDIO", method)


if __name__ == "__main__":
    unittest.main()

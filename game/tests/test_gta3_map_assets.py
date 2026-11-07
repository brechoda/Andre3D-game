from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MAP_ROOT = ROOT / "assets/source/gta3_map"
CONVERTED = MAP_ROOT / "converted_tiles"
RUNTIME_ROOT = ROOT / "assets/maps/liberty_city"
GODOT_TILES = RUNTIME_ROOT / "godot_tiles"


class Gta3MapAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.parts_manifest = json.loads((GODOT_TILES / "tile_parts.json").read_text(encoding="utf-8"))
        conversion_report_path = CONVERTED / "conversion_report.json"
        cls.conversion_report = (
            json.loads(conversion_report_path.read_text(encoding="utf-8"))
            if conversion_report_path.is_file()
            else None
        )
        cls.catalog = json.loads((RUNTIME_ROOT / "gta3_tile_catalog.json").read_text(encoding="utf-8"))

    def test_manifest_covers_all_spatial_tiles(self) -> None:
        expected = {tile["name"].replace("/", "_") for tile in self.catalog["tiles"]}
        actual = {tile["tile"].replace("/", "_") for tile in self.parts_manifest["tiles"]}
        self.assertEqual(expected, actual)
        self.assertEqual(6, self.parts_manifest["tile_count"])

    def test_split_meshes_preserve_every_triangle(self) -> None:
        if self.conversion_report is None:
            self.skipTest("source conversion report is excluded from the public runtime-assets repository")
        source_counts = {tile["tile"]: tile["faces"] for tile in self.conversion_report["tiles"]}
        split_counts = {
            tile["tile"].replace("/", "_"): tile["triangle_count"]
            for tile in self.parts_manifest["tiles"]
        }
        self.assertEqual(source_counts, split_counts)

    def test_each_mesh_is_below_godot_surface_limit_and_has_textures(self) -> None:
        for tile in self.parts_manifest["tiles"]:
            for filename in tile["parts"]:
                obj_path = GODOT_TILES / filename
                mtl_path = obj_path.with_suffix(".mtl")
                self.assertTrue(obj_path.is_file(), str(obj_path))
                self.assertTrue(mtl_path.is_file(), str(mtl_path))
                mtl_text = mtl_path.read_text(encoding="utf-8")
                material_count = sum(line.startswith("newmtl ") for line in mtl_text.splitlines())
                self.assertLessEqual(material_count, 96, str(mtl_path))
                for line in mtl_text.splitlines():
                    if line.startswith("map_Kd "):
                        texture_path = (mtl_path.parent / line[len("map_Kd "):]).resolve()
                        self.assertTrue(texture_path.is_file(), f"{mtl_path}: {texture_path}")

    def test_tile_triangle_summaries_match_obj_faces(self) -> None:
        for tile in self.parts_manifest["tiles"]:
            actual = 0
            for filename in tile["parts"]:
                obj_path = GODOT_TILES / filename
                with obj_path.open("r", encoding="utf-8", errors="replace") as obj_file:
                    actual += sum(line.startswith("f ") for line in obj_file)
            self.assertEqual(tile["triangle_count"], actual, tile["tile"])

    def test_subglass_replacements_are_present_and_translucent(self) -> None:
        report = json.loads((RUNTIME_ROOT / "subglass_repair_report.json").read_text(encoding="utf-8"))
        self.assertFalse(report["source_valid_txd"])
        self.assertEqual(1, report["patched_mtl_files"])

        mtl_path = GODOT_TILES / "landne_landne__part_12.mtl"
        mtl_text = mtl_path.read_text(encoding="utf-8")
        for material, texture in (
            ("glassfxsub1_m0_unnamed", "../textures/subglass/glassfxsub1.PNG"),
            ("glassfxsub2_m0_unnamed", "../textures/subglass/glassfxsub2.PNG"),
        ):
            with self.subTest(material=material):
                start = mtl_text.index(f"newmtl {material}")
                end = mtl_text.find("\nnewmtl ", start + 1)
                block = mtl_text[start:] if end < 0 else mtl_text[start:end]
                self.assertIn(f"map_Kd {texture}", block)
                self.assertIn("d 0.52", block)
                texture_path = (mtl_path.parent / texture).resolve()
                self.assertTrue(texture_path.is_file(), str(texture_path))
                with Image.open(texture_path) as image:
                    self.assertEqual("RGBA", image.mode)
                    alpha_min, alpha_max = image.getchannel("A").getextrema()
                    self.assertGreater(alpha_min, 0)
                    self.assertLess(alpha_max, 255)

    def test_ground_fix_assets_are_registered_for_android_runtime(self) -> None:
        streamer_path = ROOT / "scripts/gta3_map_streamer.gd"
        streamer = streamer_path.read_text(encoding="utf-8")
        self.assertIn(
            "_part_paths_by_tile[GROUND_FIX_TILE] = PackedStringArray([GROUND_FIX_VISUAL])",
            streamer,
        )
        self.assertNotIn("if FileAccess.file_exists(GROUND_FIX_VISUAL)", streamer)
        for relative_path in (
            "assets/maps/liberty_city/ground_fix/ground_fix_visual.obj",
            "assets/maps/liberty_city/ground_fix/ground_fix_visual.obj.import",
            "assets/maps/liberty_city/ground_fix/ground_fix_visual.mtl",
            "assets/maps/liberty_city/ground_fix/grass_dirt.png",
            "assets/maps/liberty_city/collisions/ground_fix_collision.obj",
            "assets/maps/liberty_city/collisions/ground_fix_collision.obj.import",
        ):
            self.assertTrue((ROOT / relative_path).is_file(), relative_path)

    def test_third_person_scene_uses_streamed_city_without_flat_ground(self) -> None:
        scene = (ROOT / "scenes/third_person.tscn").read_text(encoding="utf-8")
        self.assertIn('path="res://scripts/gta3_map_streamer.gd"', scene)
        streamer = (ROOT / "scripts/gta3_map_streamer.gd").read_text(encoding="utf-8")
        self.assertIn("res://assets/maps/liberty_city/godot_tiles/tile_parts.json", streamer)
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        self.assertIn('export_filter="all_resources"', presets)
        self.assertIn('assets/source/*,assets/maps/*', presets)
        self.assertTrue((RUNTIME_ROOT / "godot_tiles/tile_parts.json").is_file())
        self.assertIn('[node name="MapStreamer" type="Node3D" parent="."]', scene)
        self.assertIn('[node name="Player" type="CharacterBody3D" parent="."]', scene)
        self.assertIn("far = 3800.0", scene)
        self.assertNotIn('[node name="Ground" type="StaticBody3D" parent="."]', scene)

    def test_scene_fallback_spawns_match_the_validated_center_road(self) -> None:
        scene = (ROOT / "scenes/third_person.tscn").read_text(encoding="utf-8")
        self.assertIn('[node name="Player" type="CharacterBody3D" parent="."]', scene)
        self.assertIn("position = Vector3(184.73, 3.3474, -22.03)", scene)
        self.assertIn('[node name="GoreceNPC" type="CharacterBody3D" parent="."]', scene)
        self.assertIn("position = Vector3(185.0, 3.3474, -19.0)", scene)

    def test_region_spawn_points_include_player_npc_and_grounded_vehicles(self) -> None:
        regions_manifest = json.loads((RUNTIME_ROOT / "map_regions.json").read_text(encoding="utf-8"))
        regions = {region["id"]: region for region in regions_manifest["regions"]}
        self.assertEqual({"center", "level2"}, set(regions))
        center = regions["center"]
        self.assertEqual({"pop100_01", "wayfarer_01", "hilux_01", "fiatuno_01"}, set(center["vehicle_spawns"]))
        for spawn in [center["spawn"], center["gorece_spawn"], *center["vehicle_spawns"].values()]:
            self.assertEqual(3, len(spawn))
        level2 = regions["level2"]
        self.assertEqual([], level2["tiles"])
        self.assertEqual({}, level2["vehicle_spawns"])
        self.assertEqual(3, len(level2["spawn"]))
        self.assertEqual(3, len(level2["gorece_spawn"]))
        self.assertEqual([100.0, 15.0, -551.0], level2["gorece_spawn"])

        streamer = (ROOT / "scripts/gta3_map_streamer.gd").read_text(encoding="utf-8")
        third_person = (ROOT / "scripts/third_person.gd").read_text(encoding="utf-8")
        self.assertIn("func get_selected_gorece_spawn()", streamer)
        self.assertIn("func get_selected_vehicle_spawns()", streamer)
        self.assertIn('map_streamer.call("get_selected_vehicle_spawns")', third_person)
        self.assertIn('vehicle.call("sync_map_ground_after_spawn")', third_person)
        for script_name in ("pop100e2024.gd", "hilux_controller.gd", "fiatuno_controller.gd"):
            self.assertIn("func sync_map_ground_after_spawn()", (ROOT / "scripts" / script_name).read_text(encoding="utf-8"))

    def test_only_the_selected_map_region_can_be_downloaded_mounted_or_streamed(self) -> None:
        regions_manifest = json.loads((RUNTIME_ROOT / "map_regions.json").read_text(encoding="utf-8"))
        regions = {region["id"]: set(region.get("tiles", [])) for region in regions_manifest["regions"]}
        self.assertEqual({"center", "level2"}, set(regions))
        self.assertEqual(4, len(regions["center"]))
        self.assertEqual(set(), regions["level2"])
        center = next(region for region in regions_manifest["regions"] if region["id"] == "center")
        self.assertFalse(center.get("builtin", False))
        self.assertTrue(center.get("tiles"))
        catalog_names = {tile["name"] for tile in self.catalog["tiles"]}

        updater = (ROOT / "autoload/remote_updater.gd").read_text(encoding="utf-8")
        external_content = (ROOT / "autoload/external_content.gd").read_text(encoding="utf-8")
        streamer = (ROOT / "scripts/gta3_map_streamer.gd").read_text(encoding="utf-8")
        menu = (ROOT / "scripts/session_menu.gd").read_text(encoding="utf-8")
        self.assertIn("not _is_runtime_content_package(entry)", updater)
        self.assertIn("func _is_runtime_content_package", updater)
        self.assertIn("if not SUPPORTED_MAP_REGIONS.has(region_id):", updater)
        self.assertIn("const BUILTIN_REGION_IDS: Array[String] = []", external_content)
        self.assertIn("ProjectSettings.load_resource_pack(package_path, false)", external_content)
        self.assertIn("return active_region_id == region_id or RemoteUpdater.has_map_region(region_id)", external_content)
        self.assertNotIn('_mount_initial_map()', external_content)
        self.assertIn("if not active_region_id.is_empty():", external_content)
        self.assertIn("if _load_selected_region():", streamer)
        self.assertIn("func _restrict_to_selected_region()", streamer)
        self.assertIn("not _selected_region_tiles.has(tile_name)", streamer)
        self.assertIn('const SUPPORTED_REGION_IDS := ["center", "level2"]', streamer)
        self.assertIn('const STATIC_REGION_SCENE := "res://level2_static.tscn"', streamer)
        self.assertIn("func _load_static_region()", streamer)
        self.assertIn("func _build_static_region_collisions()", streamer)
        self.assertIn('collision_body.name = "COL1Collision"', streamer)
        self.assertIn("mesh_instance.mesh.create_trimesh_shape()", streamer)
        self.assertIn("collision_shapes_by_mesh[mesh_id] = collision_shape", streamer)
        self.assertIn('mesh_name.begins_with("arvore")', streamer)
        self.assertIn("if _build_static_region_collisions() == 0:", streamer)
        self.assertIn("RemoteUpdater.download_map_region(requested_region)", menu)
        self.assertEqual(1, menu.count("ExternalContent.ensure_region(selected_map_region)"))


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import json
import unittest
from pathlib import Path


GAME_ROOT = Path(__file__).resolve().parents[1]
MAP_ROOT = GAME_ROOT / "assets/maps/liberty_city"
STREAMER_PATH = GAME_ROOT / "scripts/gta3_map_streamer.gd"
MOUNTAIN_PATH = GAME_ROOT / "scripts/map_boundary_mountains.gd"


class MapBoundaryProtectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.streamer = STREAMER_PATH.read_text(encoding="utf-8")
        cls.mountains = MOUNTAIN_PATH.read_text(encoding="utf-8")
        cls.catalog = json.loads((MAP_ROOT / "gta3_tile_catalog.json").read_text(encoding="utf-8"))
        cls.regions = json.loads((MAP_ROOT / "map_regions.json").read_text(encoding="utf-8"))["regions"]

    def test_declared_region_metadata_has_spatial_bounds_for_all_its_tiles(self) -> None:
        catalog_by_name = {tile["name"]: tile for tile in self.catalog["tiles"]}
        self.assertEqual({"center", "level2"}, {region["id"] for region in self.regions})
        self.assertIn('const SUPPORTED_REGION_IDS := ["center"]', self.streamer)
        for region in self.regions:
            with self.subTest(region=region["id"]):
                if region["id"] == "level2":
                    self.assertEqual([], region["tiles"])
                    self.assertIn("func _load_static_region()", self.streamer)
                    self.assertIn('const STATIC_REGION_SCENE := "res://level2_static.tscn"', self.streamer)
                    self.assertIn("_region_bounds_min = Vector3(-753.0, -17.0, -1880.0)", self.streamer)
                    self.assertIn("_region_bounds_max = Vector3(860.0, 50.0, 520.0)", self.streamer)
                    continue
                if region.get("builtin"):
                    self.assertLess(region["bounds_min"][0], region["bounds_max"][0])
                    self.assertLess(region["bounds_min"][2], region["bounds_max"][2])
                    continue
                selected = [catalog_by_name[name] for name in region["tiles"]]
                self.assertEqual(4, len(selected))
                for tile in selected:
                    self.assertEqual(3, len(tile["bounds_min"]))
                    self.assertEqual(3, len(tile["bounds_max"]))
                min_x = min(tile["bounds_min"][0] for tile in selected)
                max_x = max(tile["bounds_max"][0] for tile in selected)
                min_y = min(tile["bounds_min"][1] for tile in selected)
                max_y = max(tile["bounds_max"][1] for tile in selected)
                self.assertLess(min_x, max_x)
                self.assertLess(min_y, max_y)

    def test_tiles_are_selected_by_bounds_and_nearest_tile_is_kept(self) -> None:
        self.assertIn("func _distance_to_tile_bounds", self.streamer)
        self.assertIn("if candidates.is_empty() and not nearest.is_empty()", self.streamer)
        self.assertNotIn("func _distance_to_tile_center", self.streamer)

    def test_visual_meshes_wait_for_their_collision_meshes(self) -> None:
        self.assertIn("for collision_pass in [true, false]", self.streamer)
        self.assertIn("not is_collision_tile_loaded(tile_name)", self.streamer)
        self.assertIn("collision_mesh.backface_collision = true", self.streamer)

    def test_selected_region_gets_an_invisible_physical_boundary(self) -> None:
        self.assertIn('const SUPPORTED_REGION_IDS := ["center"]', self.streamer)
        self.assertIn('requested_id = "center"', self.streamer)
        self.assertIn('preload("res://scripts/map_boundary_mountains.gd")', self.streamer)
        self.assertIn("_create_region_invisible_boundary()", self.streamer)
        self.assertIn('barrier.name = "InvisibleMapBoundary"', self.mountains)
        self.assertIn("func _build_water_bands()", self.mountains)
        self.assertNotIn("MountainRangeVisual", self.mountains)
        for wall_name in ("SouthWall", "NorthWall", "WestWall", "EastWall"):
            self.assertIn(f'"{wall_name}"', self.mountains)

    def test_player_and_gorece_use_void_recovery(self) -> None:
        self.assertIn("func guard_body_from_void(body: CharacterBody3D)", self.streamer)
        for script_name in ("third_person.gd", "gorece_npc.gd"):
            source = (GAME_ROOT / "scripts" / script_name).read_text(encoding="utf-8")
            self.assertIn('call("guard_body_from_void", self)', source)

    def test_regional_spawns_are_converted_from_map_coordinates_to_world(self) -> None:
        self.assertIn("func _map_coordinate_to_world(raw_position: Array) -> Vector3", self.streamer)
        self.assertIn("Vector3(float(raw_position[0]), float(raw_position[2]), float(raw_position[1]))", self.streamer)
        self.assertIn("_selected_spawn = _map_coordinate_to_world(region_spawn)", self.streamer)
        self.assertIn("func _builtin_coordinate_to_world(raw_position: Array) -> Vector3", self.streamer)
        self.assertIn("_selected_spawn = _builtin_coordinate_to_world(builtin_spawn)", self.streamer)


if __name__ == "__main__":
    unittest.main()

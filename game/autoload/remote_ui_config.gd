extends Node
## Configuração remota de aparência para elementos registrados da HUD e do menu.
## O arquivo remoto contém somente dados validados; nunca executa scripts nem escolhe NodePaths.

signal configuration_changed(revision: String)

const DEFAULT_CONFIG_PATH := "res://config/remote_ui.json"
const REMOTE_CONFIG_PATH := "config/remote_ui.json"
const MAX_CONFIG_BYTES := 64 * 1024
const ELEMENT_IDS := [
	"menu.panel", "menu.map_selector", "menu.subtitle", "menu.status",
	"menu.graphics_button", "menu.character_title", "menu.character_list",
	"menu.character.andre", "menu.character.gorece", "menu.character.dg",
	"menu.start_button", "menu.footer", "menu.download_progress", "menu.download_percent",
	"menu.loading_title", "menu.loading_status", "menu.loading_progress", "menu.loading_percent",
	"menu.graphics.panel", "menu.graphics.title", "menu.graphics.info", "menu.graphics.auto",
		"hud.root", "hud.vehicle_panel", "hud.coordinates", "hud.camera_hint",
	        "hud.touch_joystick", "hud.touch_label", "hud.run", "hud.crouch", "hud.jump",
	        "hud.action", "hud.switch", "hud.microphone", "hud.ride", "hud.follow", "hud.pull_vehicle", "hud.gps",
		"hud.gps.autopilot", "hud.gps.status", "hud.moto.accelerate", "hud.moto.brake",
	"hud.hilux.accelerate", "hud.hilux.brake", "hud.hilux.steer_left",
	"hud.hilux.steer_right", "hud.chat",
]
const VISIBILITY_IDS := [
	"menu.map_selector", "menu.subtitle", "menu.status",
	"menu.graphics_button", "menu.character_title", "menu.character_list",
	"menu.character.andre", "menu.character.gorece", "menu.character.dg",
	"menu.footer", "menu.download_progress", "menu.download_percent",
	"menu.loading_title", "menu.loading_status", "menu.loading_progress", "menu.loading_percent",
	"menu.graphics.panel", "menu.graphics.title", "menu.graphics.info", "menu.graphics.auto",
		"hud.root", "hud.vehicle_panel", "hud.coordinates", "hud.camera_hint",
	        "hud.touch_joystick", "hud.touch_label", "hud.run", "hud.crouch", "hud.jump",
	        "hud.action", "hud.switch", "hud.microphone", "hud.ride", "hud.follow", "hud.pull_vehicle", "hud.gps", "hud.chat",
	]
const TEXT_IDS := [
	"menu.subtitle", "menu.graphics_button", "menu.character_title",
	"menu.character.andre", "menu.character.gorece", "menu.character.dg",
	"menu.start_button", "menu.footer", "menu.graphics.title", "menu.graphics.info", "menu.graphics.auto",
        "hud.touch_label", "hud.run", "hud.crouch", "hud.jump", "hud.action", "hud.switch", "hud.microphone", "hud.ride", "hud.follow", "hud.pull_vehicle",
	"hud.moto.accelerate", "hud.moto.brake", "hud.hilux.accelerate", "hud.hilux.brake",
	"hud.hilux.steer_left", "hud.hilux.steer_right",
]
const OPTION_ITEM_IDS := ["menu.map_selector"]

var revision := "local"
var _element_settings: Dictionary = {}
var _registered_elements: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config_text(_read_file(DEFAULT_CONFIG_PATH), "local")
	call_deferred("_load_remote_after_update")

func register_element(element_id: String, node: Node) -> void:
	if node == null or not ELEMENT_IDS.has(element_id):
		return
	_registered_elements[element_id] = weakref(node)
	_apply_element(element_id, node)

func resolve_visibility(element_id: String, gameplay_visibility: bool) -> bool:
	if not gameplay_visibility or not VISIBILITY_IDS.has(element_id):
		return gameplay_visibility
	var settings: Dictionary = _element_settings.get(element_id, {})
	return bool(settings.get("visible", true))

func get_revision() -> String:
	return revision

func _load_remote_after_update() -> void:
	if not RemoteUpdater.is_ready:
		await RemoteUpdater.update_ready
	var remote_text: String = RemoteUpdater.read_remote_text(REMOTE_CONFIG_PATH)
	if remote_text.is_empty():
		return
	_load_config_text(remote_text, "remote")

func _load_config_text(text: String, source: String) -> void:
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_CONFIG_BYTES:
		if source == "remote":
			push_warning("RemoteUIConfig: configuração remota ausente ou acima do limite; mantendo a configuração atual")
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or int((parsed as Dictionary).get("schema_version", 0)) != 1:
		if source == "remote":
			push_warning("RemoteUIConfig: versão ou JSON remoto inválido; mantendo a configuração atual")
		return
	var raw_elements: Variant = (parsed as Dictionary).get("elements", {})
	if not raw_elements is Dictionary:
		if source == "remote":
			push_warning("RemoteUIConfig: a seção elements não é um objeto")
		return
	var sanitized: Dictionary = {}
	for element_id_variant: Variant in (raw_elements as Dictionary).keys():
		var element_id := String(element_id_variant)
		if not ELEMENT_IDS.has(element_id):
			continue
		var raw_settings: Variant = (raw_elements as Dictionary).get(element_id, {})
		if not raw_settings is Dictionary:
			continue
		var safe_settings := _sanitize_element(element_id, raw_settings as Dictionary)
		if not safe_settings.is_empty():
			sanitized[element_id] = safe_settings
	_element_settings = sanitized
	revision = str((parsed as Dictionary).get("revision", source)).substr(0, 64)
	_apply_all()
	configuration_changed.emit(revision)

func _sanitize_element(element_id: String, raw: Dictionary) -> Dictionary:
	var safe: Dictionary = {}
	if VISIBILITY_IDS.has(element_id) and typeof(raw.get("visible")) == TYPE_BOOL:
		safe["visible"] = bool(raw["visible"])
	if TEXT_IDS.has(element_id) and raw.get("text") is String:
		safe["text"] = String(raw["text"]).substr(0, 120)
	if OPTION_ITEM_IDS.has(element_id) and raw.get("items") is Array:
		var safe_items: Array[String] = []
		for item: Variant in raw["items"]:
			if item is String and safe_items.size() < 12:
				safe_items.append(String(item).substr(0, 72))
		if not safe_items.is_empty():
			safe["items"] = safe_items
	for key: String in ["position", "size", "min_size"]:
		if element_id == "menu.start_button" or not raw.has(key):
			continue
		var limits := Vector2(-4096.0, 4096.0) if key == "position" else Vector2(0.0, 4096.0)
		if key == "min_size":
			limits = Vector2(0.0, 2048.0)
		var value := _sanitize_pair(raw[key], limits.x, limits.y)
		if value.size() == 2:
			safe[key] = Vector2(value[0], value[1])
	if element_id != "menu.start_button" and typeof(raw.get("scale")) in [TYPE_INT, TYPE_FLOAT]:
		safe["scale"] = clampf(float(raw["scale"]), 0.5, 2.0)
	if typeof(raw.get("font_size")) in [TYPE_INT, TYPE_FLOAT]:
		safe["font_size"] = clampi(roundi(float(raw["font_size"])), 8, 72)
	for color_key: String in ["text_color", "background_color", "tint"]:
		var color_text: Variant = raw.get(color_key, null)
		if element_id == "menu.start_button" and color_key == "tint":
			continue
		if color_text is String and String(color_text).length() == 7 and Color.html_is_valid(color_text):
			safe[color_key] = Color.from_string(color_text, Color.WHITE)
	return safe

func _sanitize_pair(value: Variant, minimum: float, maximum: float) -> Array[float]:
	if not value is Array or (value as Array).size() != 2:
		return []
	var output: Array[float] = []
	for component: Variant in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return []
		output.append(clampf(float(component), minimum, maximum))
	return output

func _apply_all() -> void:
	for element_id_variant: Variant in _registered_elements.keys():
		var element_id := String(element_id_variant)
		var reference := _registered_elements[element_id] as WeakRef
		var node := reference.get_ref() as Node if reference != null else null
		if node == null or not is_instance_valid(node):
			_registered_elements.erase(element_id)
			continue
		_apply_element(element_id, node)

func _apply_element(element_id: String, node: Node) -> void:
	var settings: Dictionary = _element_settings.get(element_id, {})
	if settings.is_empty():
		return
	if VISIBILITY_IDS.has(element_id) and settings.has("visible") and node is CanvasItem:
		(node as CanvasItem).visible = bool(settings["visible"])
	if node is Control:
		var control := node as Control
		if settings.has("position"):
			control.position = settings["position"] as Vector2
		if settings.has("size"):
			control.size = settings["size"] as Vector2
		if settings.has("min_size"):
			control.custom_minimum_size = settings["min_size"] as Vector2
		if settings.has("font_size"):
			control.add_theme_font_size_override("font_size", int(settings["font_size"]))
		if settings.has("text_color"):
			control.add_theme_color_override("font_color", settings["text_color"] as Color)
		if node is OptionButton and settings.has("items"):
			var option := node as OptionButton
			var items: Array = settings["items"]
			for index in range(mini(option.item_count, items.size())):
				option.set_item_text(index, String(items[index]))
		elif node is Label and settings.has("text"):
			(node as Label).text = String(settings["text"])
		elif node is Button and settings.has("text"):
			(node as Button).text = String(settings["text"])
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		if settings.has("scale"):
			canvas_item.scale = Vector2.ONE * float(settings["scale"])
		if settings.has("tint"):
			canvas_item.modulate = settings["tint"] as Color
	if node is ColorRect and settings.has("background_color"):
		(node as ColorRect).color = settings["background_color"] as Color
	elif node is PanelContainer and settings.has("background_color"):
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = settings["background_color"] as Color
		(node as PanelContainer).add_theme_stylebox_override("panel", panel_style)

func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()

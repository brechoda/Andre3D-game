extends Node

## Monta os pacotes regionais do mapa sem duplicá-los dentro do APK.

signal status_changed(message: String)

var map_ready := false
var map_pack_path := ""
var status_message := "Pacote do mapa não instalado."
var _mounted_regions: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_mount_initial_map")

func _mount_initial_map() -> void:
	status_message = "Procurando pacote do mapa principal..."
	status_changed.emit(status_message)
	await RemoteUpdater.wait_until_ready()
	if await ensure_region("industrial"):
		return
	status_message = "Baixe o mapa principal INDUSTRIAL para jogar."
	status_changed.emit(status_message)

func ensure_region(region_id: String) -> bool:
	if _mounted_regions.has(region_id):
		map_ready = true
		return true
	var package_path := RemoteUpdater.get_map_package_path(region_id)
	if package_path.is_empty() or not FileAccess.file_exists(package_path):
		return false
	status_message = "Carregando mapa %s..." % region_id
	status_changed.emit(status_message)
	if not ProjectSettings.load_resource_pack(package_path, false):
		status_message = "Não foi possível abrir o mapa %s." % region_id
		status_changed.emit(status_message)
		return false
	_mounted_regions[region_id] = package_path
	map_pack_path = package_path
	map_ready = true
	status_message = "Mapa %s pronto." % region_id
	status_changed.emit(status_message)
	return true

func is_map_available() -> bool:
	return map_ready

func is_region_available(region_id: String) -> bool:
	return _mounted_regions.has(region_id) or RemoteUpdater.has_map_region(region_id)

func get_status_message() -> String:
	return status_message

func get_install_path_hint() -> String:
	return "Android/data/com.manus.andre3d.next/files/content/Andre3D-map-center.pck"

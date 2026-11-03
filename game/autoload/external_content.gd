extends Node
## Monta somente a região escolhida pelo jogador; PCKs regionais não são pré-carregados.

signal status_changed(message: String)

const SUPPORTED_REGION_IDS := ["industrial", "center", "costa_vista"]
const BUILTIN_REGION_IDS := ["costa_vista"]

var map_ready := false
var map_pack_path := ""
var status_message := "Nenhum mapa foi carregado."
var active_region_id := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Não monte um mapa padrão no boot. O menu prepara o download da seleção e
	# ensure_region() é chamado somente no início do jogo.

func ensure_region(region_id: String) -> bool:
	if not SUPPORTED_REGION_IDS.has(region_id):
		status_message = "A região solicitada não é uma opção de mapa válida."
		status_changed.emit(status_message)
		return false
	if active_region_id == region_id:
		map_ready = true
		return true
	if not active_region_id.is_empty():
		status_message = "O mapa %s já foi carregado. Feche e reabra o jogo para escolher outro." % active_region_id.to_upper()
		status_changed.emit(status_message)
		return false
	if BUILTIN_REGION_IDS.has(region_id):
		active_region_id = region_id
		map_ready = true
		status_message = "Mapa %s pronto." % region_id.to_upper()
		status_changed.emit(status_message)
		return true
	var package_path: String = RemoteUpdater.get_map_package_path(region_id)
	if package_path.is_empty() or not FileAccess.file_exists(package_path):
		status_message = "O mapa %s ainda não foi baixado." % region_id.to_upper()
		status_changed.emit(status_message)
		return false
	status_message = "Carregando somente o mapa %s..." % region_id.to_upper()
	status_changed.emit(status_message)
	if not ProjectSettings.load_resource_pack(package_path, false):
		status_message = "Não foi possível abrir o mapa %s." % region_id.to_upper()
		status_changed.emit(status_message)
		return false
	active_region_id = region_id
	map_pack_path = package_path
	map_ready = true
	status_message = "Mapa %s pronto." % region_id.to_upper()
	status_changed.emit(status_message)
	return true

func is_map_available() -> bool:
	return map_ready

func is_region_available(region_id: String) -> bool:
	if not SUPPORTED_REGION_IDS.has(region_id):
		return false
	if BUILTIN_REGION_IDS.has(region_id):
		return true
	return active_region_id == region_id or RemoteUpdater.has_map_region(region_id)

func get_active_region_id() -> String:
	return active_region_id

func get_status_message() -> String:
	return status_message

func get_install_path_hint() -> String:
	var region_id := active_region_id if not active_region_id.is_empty() else "industrial"
	return "Android/data/com.manus.andre3d.next/files/content/Andre3D-map-%s.pck" % region_id

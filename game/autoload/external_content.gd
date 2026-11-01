extends Node

## Monta conteúdo Godot externo sem duplicá-lo dentro do APK.
## O arquivo é um PCK Godot; a extensão pode ser .pck ou .obb.

signal status_changed(message: String)

const MAP_PACK_CANDIDATES := [
    "user://content/Andre3D-map.pck",
    "user://content/Andre3D-map.obb",
    "user://Andre3D-map.pck",
    "user://Andre3D-map.obb",
    "user://updates/packages/Andre3D-map.pck",
]

var map_ready := false
var map_pack_path := ""
var status_message := "Pacote do mapa não instalado."

func _ready() -> void:
    call_deferred("_mount_map_pack")

func _mount_map_pack() -> void:
    status_message = "Procurando pacote do mapa..."
    status_changed.emit(status_message)
    if _try_mount_map_pack():
        return
    # O RemoteUpdater pode baixar o PCK para user://content durante a inicialização.
    # Aguarde o resultado antes de bloquear o botão de entrada no menu.
    await RemoteUpdater.wait_until_ready()
    if _try_mount_map_pack():
        return
    status_message = "Instale Andre3D-map.pck em user://content/."
    status_changed.emit(status_message)

func _try_mount_map_pack() -> bool:
    for path: String in MAP_PACK_CANDIDATES:
        if not FileAccess.file_exists(path):
            continue
        status_message = "Carregando mapa..."
        status_changed.emit(status_message)
        if ProjectSettings.load_resource_pack(path, false):
            map_ready = true
            map_pack_path = path
            status_message = "Mapa pronto."
            status_changed.emit(status_message)
            return true
        status_message = "Não foi possível abrir o pacote do mapa."
        status_changed.emit(status_message)
        return false
    return false

func is_map_available() -> bool:
    return map_ready

func get_status_message() -> String:
    return status_message

func get_install_path_hint() -> String:
    return "Android/data/com.manus.andre3d.next/files/content/Andre3D-map.pck"

extends Node
## Baixa conteúdo versionado depois que o APK já foi instalado.
## O APK continua sendo a base; arquivos remotos nunca substituem código nativo sem validação.

signal update_status_changed(message: String, progress: float)
signal update_ready(success: bool, message: String)

const UPDATE_CONFIG_PATH := "res://config/updates.json"
const CACHE_ROOT := "user://updates"
const FILE_CACHE_ROOT := "user://updates/files"
const PACKAGE_CACHE_ROOT := "user://updates/packages"
const CONTENT_ROOT := "user://content"
const INSTALLED_MANIFEST_PATH := "user://updates/installed.json"
const UPDATE_PREFS_PATH := "user://andre3d_update_preferences.json"
const MAX_MANIFEST_BYTES := 256 * 1024
const MAX_FILE_BYTES := 256 * 1024 * 1024
const MAX_APK_BYTES := 512 * 1024 * 1024

var is_ready := false
var update_succeeded := true
var status_message := ""
var auto_download_apk := true
var client_update_available := false
var client_update_downloaded := false
var client_update_version := ""
var client_update_url := ""
var client_update_sha256 := ""
var client_update_size := 0
var min_online_version := "0.0.0"
var _client_apk_path := ""
var _manifest: Dictionary = {}
var _http: HTTPRequest
var _http_completed := false
var _http_result: Array = []

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _ensure_cache_dirs()
    auto_download_apk = bool(_load_json_file(UPDATE_PREFS_PATH).get("auto_download_apk", true))
    call_deferred("_start_update_check")

func wait_until_ready(timeout_seconds: float = -1.0) -> bool:
    if is_ready:
        return update_succeeded
    if timeout_seconds <= 0.0:
        await update_ready
        return update_succeeded
    var elapsed := 0.0
    while not is_ready and elapsed < timeout_seconds:
        await get_tree().create_timer(0.1).timeout
        elapsed += 0.1
    return update_succeeded

func get_status_message() -> String:
    return status_message

func set_auto_download_apk(enabled: bool) -> void:
    auto_download_apk = enabled
    _write_json(UPDATE_PREFS_PATH, {"auto_download_apk": enabled})

func get_app_version() -> String:
    return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

func can_play_online() -> bool:
    return _compare_versions(get_app_version(), min_online_version) >= 0

func get_online_block_message() -> String:
    return "Atualize o APK para a versão %s para jogar online." % min_online_version

func get_client_update_message() -> String:
    if not client_update_available:
        return ""
    if client_update_downloaded:
        return "Versão %s baixada. Instale a atualização e abra o jogo novamente." % client_update_version
    if auto_download_apk:
        return "Nova versão %s encontrada; baixando automaticamente..." % client_update_version
    return "Nova versão %s disponível. Ative o download automático nas opções." % client_update_version

func is_client_update_required() -> bool:
    return client_update_available

func install_downloaded_apk() -> bool:
    if _client_apk_path.is_empty() or not FileAccess.file_exists(_client_apk_path):
        return false
    return OS.shell_open(ProjectSettings.globalize_path(_client_apk_path)) == OK

func has_remote_file(relative_path: String) -> bool:
    return FileAccess.file_exists(_cache_file_path(relative_path))

func read_remote_text(relative_path: String) -> String:
    var path := _cache_file_path(relative_path)
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return "" if file == null else file.get_as_text()

func _start_update_check() -> void:
    var config := _load_json_file(UPDATE_CONFIG_PATH)
    var manifest_url := str(config.get("manifest_url", ""))
    if manifest_url.is_empty():
        _finish(true, "Atualizações remotas desativadas")
        return
    # O plugin Android registra o manifesto e inicia um Foreground Service
    # quando o usuário minimiza o app. Em outras plataformas, o fluxo Godot
    # continua sendo usado normalmente.
    if OS.has_feature("android") and Engine.has_singleton("BackgroundUpdate"):
        Engine.get_singleton("BackgroundUpdate").configure_background_update(manifest_url)

    _emit_status("Verificando atualizações...", 0.0)
    var response := await _http_get(manifest_url, MAX_MANIFEST_BYTES)
    if not bool(response.get("ok", false)):
        _finish(true, "Servidor de atualizações indisponível; usando cache local")
        return

    var parsed: Variant = JSON.parse_string((response.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
    if not parsed is Dictionary:
        _finish(true, "Manifesto inválido; usando cache local")
        return
    _manifest = parsed

    var validation := _validate_manifest(_manifest)
    if not bool(validation.get("ok", false)):
        _finish(true, "Manifesto rejeitado; usando cache local")
        return

    _inspect_client_update(_manifest, manifest_url)

    var packages: Array = _manifest.get("files", [])
    var total := packages.size()
    var index := 0
    for entry_variant: Variant in packages:
        index += 1
        var entry: Dictionary = entry_variant
        var relative_path := str(entry.get("path", ""))
        var kind := str(entry.get("kind", "file"))
        var destination := _cache_file_path(relative_path) if kind != "pck" else _cache_package_path(relative_path)
        if _is_cached_file_valid(destination, entry):
            _emit_status("Conteúdo %d/%d já está instalado" % [index, total], float(index) / maxf(1.0, float(total)))
            continue
        _emit_status("Baixando conteúdo %d/%d..." % [index, total], float(index - 1) / maxf(1.0, float(total)))
        var file_response := await _http_get(_resolve_url(manifest_url, str(entry.get("url", ""))), MAX_FILE_BYTES, "Baixando conteúdo", int(entry.get("size", 0)))
        if not bool(file_response.get("ok", false)):
            _finish(true, "Falha no download; usando cache local")
            return
        var body: PackedByteArray = file_response.get("body", PackedByteArray())
        if not _body_matches_entry(body, entry):
            _finish(true, "Hash inválido; atualização ignorada")
            return
        if not _store_bytes(destination, body):
            _finish(true, "Não foi possível salvar a atualização")
            return

    _write_json(INSTALLED_MANIFEST_PATH, _manifest)
    _load_cached_packs(packages)
    _finish(true, "Atualização remota verificada")
    if client_update_available:
        # Atualização obrigatória: o menu não libera a entrada enquanto o APK
        # novo não estiver baixado e pronto para instalação.
        await _download_client_apk()

func _inspect_client_update(manifest: Dictionary, manifest_url: String) -> void:
    var client: Variant = manifest.get("client", {})
    if not client is Dictionary:
        return
    client_update_version = str(client.get("version", ""))
    client_update_url = _resolve_url(manifest_url, str(client.get("url", "")))
    client_update_sha256 = str(client.get("sha256", "")).to_lower()
    client_update_size = int(client.get("size", 0))
    min_online_version = str(manifest.get("min_online_version", "0.0.0"))
    client_update_available = not client_update_version.is_empty() and _compare_versions(client_update_version, get_app_version()) > 0
    if client_update_available:
        _client_apk_path = "user://updates/apk/Andre3D-%s.apk" % client_update_version
        client_update_downloaded = _is_cached_file_valid(_client_apk_path, {"size": client_update_size, "sha256": client_update_sha256})

func _download_client_apk() -> void:
    if not client_update_available or client_update_downloaded or client_update_url.is_empty():
        return
    _emit_status("Baixando atualização do APK... 0%", 0.0)
    var response := await _http_get(client_update_url, MAX_APK_BYTES, "Baixando atualização do APK", client_update_size)
    if not bool(response.get("ok", false)):
        _emit_status("Não foi possível baixar o APK; usando a versão atual", 1.0)
        return
    var body: PackedByteArray = response.get("body", PackedByteArray())
    if not _body_matches_entry(body, {"size": client_update_size, "sha256": client_update_sha256}):
        _emit_status("Hash do APK inválido; atualização ignorada", 1.0)
        return
    client_update_downloaded = _store_bytes(_client_apk_path, body)
    _emit_status("Download da versão %s concluído (100%%). Toque em INSTALAR APK BAIXADO." % client_update_version, 1.0)

func _validate_manifest(manifest: Dictionary) -> Dictionary:
    var version := str(manifest.get("version", ""))
    if version.is_empty() or version.length() > 64:
        return {"ok": false}
    var files: Variant = manifest.get("files", [])
    if not files is Array or files.size() > 64:
        return {"ok": false}
    for entry_variant: Variant in files:
        if not entry_variant is Dictionary:
            return {"ok": false}
        var entry: Dictionary = entry_variant
        var relative_path := str(entry.get("path", ""))
        var sha256 := str(entry.get("sha256", ""))
        var size := int(entry.get("size", -1))
        var kind := str(entry.get("kind", "file"))
        if not _is_safe_relative_path(relative_path) or sha256.length() != 64 or size < 0 or size > MAX_FILE_BYTES:
            return {"ok": false}
        if kind not in ["file", "pck"]:
            return {"ok": false}
        if str(entry.get("url", "")).is_empty():
            return {"ok": false}
    return {"ok": true}

func _compare_versions(left: String, right: String) -> int:
    var left_parts := left.split(".")
    var right_parts := right.split(".")
    for index in range(3):
        var left_value := int(left_parts[index]) if index < left_parts.size() else 0
        var right_value := int(right_parts[index]) if index < right_parts.size() else 0
        if left_value != right_value:
            return 1 if left_value > right_value else -1
    return 0

func _load_cached_packs(files: Array) -> void:
    for entry_variant: Variant in files:
        var entry: Dictionary = entry_variant
        if str(entry.get("kind", "file")) != "pck":
            continue
        var package_path := _cache_package_path(str(entry.get("path", "")))
        if FileAccess.file_exists(package_path):
            if not ProjectSettings.load_resource_pack(package_path, true):
                push_warning("RemoteUpdater: pacote PCK não pôde ser carregado: " + package_path)

func _http_get(url: String, max_bytes: int, progress_label: String = "", expected_bytes: int = 0) -> Dictionary:
    if url.is_empty() or not (url.begins_with("https://") or url.begins_with("http://")):
        return {"ok": false}
    var request := HTTPRequest.new()
    request.timeout = 600.0 if max_bytes >= 64 * 1024 * 1024 else 25.0
    var temporary_path := FILE_CACHE_ROOT + "/.download-%d.tmp" % Time.get_ticks_usec()
    request.download_file = temporary_path
    add_child(request)
    _http_completed = false
    _http_result = []
    request.request_completed.connect(_on_http_request_completed)
    # Conecte o sinal antes de iniciar a requisição. Se a resposta for muito
    # rápida e o sinal for conectado depois de request(), o menu pode esperar
    # para sempre por uma resposta que já aconteceu.
    var error := request.request(url)
    if error != OK:
        request.queue_free()
        return {"ok": false}
    var deadline_ms := 600000 if max_bytes >= 64 * 1024 * 1024 else 30000
    var deadline := Time.get_ticks_msec() + deadline_ms
    var last_progress_tick := 0
    while not _http_completed and Time.get_ticks_msec() < deadline:
        var now := Time.get_ticks_msec()
        if not progress_label.is_empty() and now - last_progress_tick >= 100:
            last_progress_tick = now
            var total_bytes := expected_bytes
            var downloaded_bytes := 0
            var partial := FileAccess.open(temporary_path, FileAccess.READ)
            if partial != null:
                downloaded_bytes = partial.get_length()
                partial.close()
            if total_bytes > 0:
                var progress := clampf(float(downloaded_bytes) / float(total_bytes), 0.0, 1.0)
                _emit_status("%s... %d%% (%s / %s)" % [progress_label, int(round(progress * 100.0)), _format_bytes(downloaded_bytes), _format_bytes(total_bytes)], progress)
        await get_tree().process_frame
    request.queue_free()
    if not _http_completed:
        if FileAccess.file_exists(temporary_path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
        return {"ok": false}
    var body := PackedByteArray()
    var downloaded := FileAccess.open(temporary_path, FileAccess.READ)
    if downloaded != null:
        body = downloaded.get_buffer(max_bytes + 1)
        downloaded.close()
    if FileAccess.file_exists(temporary_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
    if body.size() > max_bytes:
        return {"ok": false}
    return {"ok": int(_http_result[1]) >= 200 and int(_http_result[1]) < 300, "body": body}

func _on_http_request_completed(result_code: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    _http_completed = true
    _http_result = [result_code, response_code, headers, body]

func _format_bytes(value: int) -> String:
    if value >= 1024 * 1024:
        return "%.1f MB" % (float(value) / (1024.0 * 1024.0))
    return "%.1f KB" % (float(value) / 1024.0)

func _is_cached_file_valid(path: String, entry: Dictionary) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var data := file.get_buffer(MAX_FILE_BYTES + 1)
    return _body_matches_entry(data, entry)

func _body_matches_entry(body: PackedByteArray, entry: Dictionary) -> bool:
    return body.size() == int(entry.get("size", -1)) and _sha256_hex(body) == str(entry.get("sha256", "")).to_lower()

func _sha256_hex(body: PackedByteArray) -> String:
    var hashing := HashingContext.new()
    if hashing.start(HashingContext.HASH_SHA256) != OK:
        return ""
    hashing.update(body)
    return hashing.finish().hex_encode().to_lower()

func _store_bytes(path: String, body: PackedByteArray) -> bool:
    var absolute := ProjectSettings.globalize_path(path)
    var parent := absolute.get_base_dir()
    if DirAccess.make_dir_recursive_absolute(parent) != OK and not DirAccess.dir_exists_absolute(parent):
        return false
    var temporary := path + ".tmp"
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return false
    file.store_buffer(body)
    file.close()
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute) == OK

func _write_json(path: String, value: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(value, "  "))

func _load_json_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed if parsed is Dictionary else {}

func _ensure_cache_dirs() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILE_CACHE_ROOT))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACKAGE_CACHE_ROOT))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT_ROOT))

func _cache_file_path(relative_path: String) -> String:
    return FILE_CACHE_ROOT + "/" + relative_path

func _cache_package_path(relative_path: String) -> String:
    if relative_path.get_file() == "Andre3D-map.pck":
        return CONTENT_ROOT + "/Andre3D-map.pck"
    return PACKAGE_CACHE_ROOT + "/" + relative_path.get_file()

func _is_safe_relative_path(path: String) -> bool:
    return not path.is_empty() and not path.begins_with("/") and not path.contains("..") and not path.contains("\\")

func _resolve_url(manifest_url: String, file_url: String) -> String:
    if file_url.begins_with("http://") or file_url.begins_with("https://"):
        return file_url
    var base := manifest_url.get_base_dir()
    if file_url.begins_with("/"):
        var scheme_end := manifest_url.find("://")
        var host_end := manifest_url.find("/", scheme_end + 3)
        return manifest_url.left(host_end if host_end >= 0 else manifest_url.length()) + file_url
    return base.rstrip("/") + "/" + file_url.lstrip("/")

func _emit_status(message: String, progress: float) -> void:
    status_message = message
    update_status_changed.emit(message, clampf(progress, 0.0, 1.0))

func _finish(success: bool, message: String) -> void:
    update_succeeded = success
    status_message = message
    is_ready = true
    update_status_changed.emit(message, 1.0)
    update_ready.emit(success, message)

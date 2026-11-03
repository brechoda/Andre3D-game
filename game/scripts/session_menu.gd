extends Control

const SESSION_PATH := "user://andre3d_session.json"
const GAME_SCENE := "res://scenes/third_person.tscn"
const LOADING_ART_PATH := "res://assets/template/ui/loading_gta.png"

var selected_mode := "online"
var selected_character := "andre"
var selected_map_region := "industrial"
var mode_hint: Label
var character_box: VBoxContainer
var map_region_option: OptionButton
var start_button: Button
var _loading := false
var _loading_overlay: Control
var _loading_progress: ProgressBar
var _loading_percent: Label
var _loading_status: Label
var _download_overlay: Control
var _download_progress: ProgressBar
var _download_percent: Label
var _install_update_button: Button
var _remote_update_ready := false
var _map_content_ready := false
var _map_region_loading := false
var _graphics_overlay: Control
var _graphics_distance: OptionButton
var _graphics_texture: OptionButton
var _graphics_resolution: OptionButton
var _graphics_auto: CheckButton

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_menu()
    # Mantém a tela de progresso visível até o conteúdo inicial estar pronto.
    _show_download_screen()
    ExternalContent.status_changed.connect(_on_map_content_status)
    _map_content_ready = ExternalContent.is_map_available()
    RemoteUpdater.update_status_changed.connect(_on_remote_update_status)
    start_button.disabled = true
    call_deferred("_wait_for_remote_update")

func _on_map_content_status(message: String) -> void:
    _map_content_ready = ExternalContent.is_region_available(selected_map_region)
    if mode_hint != null and not message.is_empty() and _map_region_loading:
        mode_hint.text = message
    _sync_download_gate()

func _wait_for_remote_update() -> void:
    await RemoteUpdater.wait_until_ready()
    _remote_update_ready = true
    if not RemoteUpdater.is_client_update_required():
        call_deferred("_request_notification_permission")
        call_deferred("_prepare_selected_map")
    _sync_download_gate()
    if mode_hint != null:
        var update_message := RemoteUpdater.get_status_message()
        mode_hint.text = "ONLINE: conecta automaticamente à sala ANDRE3D."
        if RemoteUpdater.is_client_update_required():
            mode_hint.text = RemoteUpdater.get_client_update_message()
        elif selected_mode == "online" and not RemoteUpdater.can_play_online():
            mode_hint.text = RemoteUpdater.get_online_block_message()
        if not RemoteUpdater.is_client_update_required() and not update_message.is_empty() and not RemoteUpdater.update_succeeded:
            mode_hint.text += "\n" + update_message
    _refresh_update_action()

func _request_notification_permission() -> void:
    if not OS.has_feature("android"):
        return
    var permission := "android.permission.POST_NOTIFICATIONS"
    if OS.has_method("get_granted_permissions"):
        var granted_permissions: PackedStringArray = OS.get_granted_permissions()
        if permission in granted_permissions:
            return
    OS.request_permission(permission)

func _on_remote_update_status(message: String, progress: float) -> void:
    if _download_progress != null:
        _download_progress.value = clampf(progress, 0.0, 1.0) * 100.0
    if _download_percent != null:
        _download_percent.text = "%d%%" % int(round(clampf(progress, 0.0, 1.0) * 100.0))
    if mode_hint != null and RemoteUpdater.is_client_update_required():
        mode_hint.text = message
    _sync_download_gate()
    _refresh_update_action()

func _sync_download_gate() -> void:
    var ready := _map_content_ready and _remote_update_ready and not _map_region_loading
    if start_button != null:
        start_button.disabled = not ready or RemoteUpdater.is_client_update_required()
    if (ready or RemoteUpdater.is_client_update_required()) and _download_overlay != null:
        _download_overlay.visible = false

func _refresh_update_action() -> void:
    if _install_update_button == null:
        return
    var required := RemoteUpdater.is_client_update_required()
    _install_update_button.visible = required and (RemoteUpdater.client_update_downloaded or RemoteUpdater.client_update_download_failed)
    _install_update_button.disabled = RemoteUpdater.client_update_download_in_progress
    _install_update_button.text = "INSTALAR ATUALIZAÇÃO" if RemoteUpdater.client_update_downloaded else "TENTAR BAIXAR APK"

func _on_update_action_pressed() -> void:
    if RemoteUpdater.client_update_downloaded:
        if not RemoteUpdater.install_downloaded_apk():
            mode_hint.text = "Não foi possível abrir o instalador. Tente novamente."
        else:
            mode_hint.text = "Confirme a instalação do APK no Android. Depois, abra o jogo novamente."
        return
    call_deferred("_retry_required_apk_download")

func _retry_required_apk_download() -> void:
    await RemoteUpdater.download_client_apk()
    _refresh_update_action()

func _show_download_screen() -> void:
    _download_overlay = Control.new()
    _download_overlay.name = "DownloadProgressScreen"
    _download_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _download_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _download_overlay.z_index = 200
    add_child(_download_overlay)

    var background := ColorRect.new()
    background.color = Color("071017")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _download_overlay.add_child(background)

    _download_progress = ProgressBar.new()
    _download_progress.max_value = 100.0
    _download_progress.value = 0.0
    _download_progress.show_percentage = false
    _download_progress.custom_minimum_size = Vector2(300.0, 18.0)
    _download_progress.set_anchors_preset(Control.PRESET_CENTER)
    _download_progress.position = Vector2(-150.0, -9.0)
    _download_progress.size = Vector2(300.0, 18.0)
    _download_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _download_overlay.add_child(_download_progress)
    RemoteUIConfig.register_element("menu.download_progress", _download_progress)

    _download_percent = Label.new()
    _download_percent.text = "0%"
    _download_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _download_percent.add_theme_font_size_override("font_size", 22)
    _download_percent.add_theme_color_override("font_color", Color.WHITE)
    _download_percent.set_anchors_preset(Control.PRESET_CENTER)
    _download_percent.position = Vector2(-60.0, 18.0)
    _download_percent.size = Vector2(120.0, 34.0)
    _download_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _download_overlay.add_child(_download_percent)
    RemoteUIConfig.register_element("menu.download_percent", _download_percent)

func _process(_delta: float) -> void:
    if not _loading:
        return
    var progress_values: Array = []
    var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress_values)
    var progress := 0.0
    if not progress_values.is_empty():
        progress = clampf(float(progress_values[0]), 0.0, 1.0)
    _set_loading_progress(progress)
    if status == ResourceLoader.THREAD_LOAD_LOADED:
        var packed := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
        if packed == null:
            _loading_failed("Não foi possível preparar o mapa.")
            return
        _loading_status.text = "Entrando na cidade..."
        _set_loading_progress(1.0)
        _loading = false
        get_tree().change_scene_to_packed(packed)
    elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
        _loading_failed("Falha ao carregar os arquivos do mapa.")

func _build_menu() -> void:
    var background := ColorRect.new()
    background.color = Color("09151b")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(460, 520)
    center.add_child(panel)
    RemoteUIConfig.register_element("menu.panel", panel)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 14)
    content.alignment = BoxContainer.ALIGNMENT_BEGIN
    panel.add_child(content)
    map_region_option = OptionButton.new()
    map_region_option.custom_minimum_size = Vector2(360, 44)
    map_region_option.add_item("INDUSTRIAL — principal, menor pacote")
    map_region_option.add_item("CENTRO — bairros comerciais")
    map_region_option.item_selected.connect(_select_map_region)
    content.add_child(map_region_option)
    RemoteUIConfig.register_element("menu.map_selector", map_region_option)
    var subtitle := Label.new()
    subtitle.text = "ESCOLHA COMO JOGAR"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 18)
    content.add_child(subtitle)
    RemoteUIConfig.register_element("menu.subtitle", subtitle)
    mode_hint = Label.new()
    mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    mode_hint.custom_minimum_size = Vector2(400, 42)
    content.add_child(mode_hint)
    RemoteUIConfig.register_element("menu.status", mode_hint)
    _install_update_button = _make_button("INSTALAR ATUALIZAÇÃO")
    _install_update_button.visible = false
    _install_update_button.pressed.connect(_on_update_action_pressed)
    content.add_child(_install_update_button)
    var graphics_button := _make_button("CONFIGURAÇÕES GRÁFICAS")
    graphics_button.pressed.connect(_open_graphics_menu)
    content.add_child(graphics_button)
    RemoteUIConfig.register_element("menu.graphics_button", graphics_button)
    var character_title := Label.new()
    character_title.text = "PERSONAGEM"
    character_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    character_title.add_theme_font_size_override("font_size", 16)
    content.add_child(character_title)
    RemoteUIConfig.register_element("menu.character_title", character_title)
    character_box = VBoxContainer.new()
    character_box.add_theme_constant_override("separation", 8)
    content.add_child(character_box)
    RemoteUIConfig.register_element("menu.character_list", character_box)
    var andre_button := _make_button("ANDRÉ")
    var gorece_button := _make_button("GORECE")
    var dg_button := _make_button("DG")
    character_box.add_child(andre_button)
    character_box.add_child(gorece_button)
    character_box.add_child(dg_button)
    RemoteUIConfig.register_element("menu.character.andre", andre_button)
    RemoteUIConfig.register_element("menu.character.gorece", gorece_button)
    RemoteUIConfig.register_element("menu.character.dg", dg_button)
    andre_button.pressed.connect(func() -> void: _select_character("andre"))
    gorece_button.pressed.connect(func() -> void: _select_character("gorece"))
    dg_button.pressed.connect(func() -> void: _select_character("dg"))
    start_button = _make_button("ENTRAR NO JOGO")
    start_button.custom_minimum_size = Vector2(0, 54)
    content.add_child(start_button)
    RemoteUIConfig.register_element("menu.start_button", start_button)
    start_button.pressed.connect(_start_game)
    var footer := Label.new()
    footer.text = "No online, o outro jogador aparece como personagem escolhido."
    footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    footer.add_theme_font_size_override("font_size", 13)
    content.add_child(footer)
    RemoteUIConfig.register_element("menu.footer", footer)
    _select_mode("online")
    _select_map_region(0)
    _select_character("andre")

func _open_graphics_menu() -> void:
    if _graphics_overlay != null:
        _graphics_overlay.visible = true
        _refresh_graphics_controls()
        return
    _graphics_overlay = Control.new()
    _graphics_overlay.name = "GraphicsConfirmationMenu"
    _graphics_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _graphics_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _graphics_overlay.z_index = 300
    add_child(_graphics_overlay)

    var shade := ColorRect.new()
    shade.color = Color(0.01, 0.02, 0.03, 0.86)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _graphics_overlay.add_child(shade)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _graphics_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(560, 530)
    center.add_child(panel)
    RemoteUIConfig.register_element("menu.graphics.panel", panel)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 12)
    content.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(content)

    var title := Label.new()
    title.text = "CONFIGURAÇÕES GRÁFICAS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 26)
    content.add_child(title)
    RemoteUIConfig.register_element("menu.graphics.title", title)
    var info := Label.new()
    info.text = "Escolha os níveis e confirme para aplicar.\nO modo automático ajusta aos poucos quando o FPS fica abaixo de 30."
    info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(info)
    RemoteUIConfig.register_element("menu.graphics.info", info)

    _graphics_distance = _graphics_option(content, "DISTÂNCIA DE RENDERIZAÇÃO", GraphicsSettings.RENDER_DISTANCE_NAMES)
    _graphics_texture = _graphics_option(content, "QUALIDADE DAS TEXTURAS", GraphicsSettings.TEXTURE_QUALITY_NAMES)
    _graphics_resolution = _graphics_option(content, "RESOLUÇÃO 3D", ["50%", "65%", "82%", "100%"] )
    _graphics_auto = CheckButton.new()
    _graphics_auto.text = "MODO AUTOMÁTICO DE OTIMIZAÇÃO"
    _graphics_auto.tooltip_text = "Reduz a qualidade gradualmente se o FPS ficar abaixo de 30 e recupera após estabilidade."
    content.add_child(_graphics_auto)
    RemoteUIConfig.register_element("menu.graphics.auto", _graphics_auto)

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 12)
    content.add_child(buttons)
    var cancel := _make_button("CANCELAR")
    cancel.pressed.connect(func() -> void: _graphics_overlay.visible = false)
    buttons.add_child(cancel)
    var confirm := _make_button("CONFIRMAR CONFIGURAÇÕES")
    confirm.pressed.connect(_confirm_graphics_settings)
    buttons.add_child(confirm)
    _refresh_graphics_controls()

func _graphics_option(parent: VBoxContainer, title_text: String, options: Array) -> OptionButton:
    var label := Label.new()
    label.text = title_text
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    parent.add_child(label)
    var option := OptionButton.new()
    option.custom_minimum_size = Vector2(360, 42)
    for value in options:
        option.add_item(str(value))
    parent.add_child(option)
    return option

func _refresh_graphics_controls() -> void:
    if _graphics_distance == null:
        return
    _graphics_distance.select(GraphicsSettings.render_distance_level)
    _graphics_texture.select(GraphicsSettings.texture_quality_level)
    _graphics_resolution.select(GraphicsSettings.resolution_level)
    _graphics_auto.button_pressed = GraphicsSettings.automatic_optimization

func _confirm_graphics_settings() -> void:
    GraphicsSettings.configure(_graphics_distance.selected, _graphics_texture.selected, _graphics_resolution.selected, _graphics_auto.button_pressed)
    _graphics_overlay.visible = false
    mode_hint.text = "Configurações gráficas aplicadas."

func _make_button(text_value: String) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = Vector2(190, 48)
    button.add_theme_font_size_override("font_size", 18)
    return button

func _select_mode(mode: String) -> void:
    selected_mode = mode
    if mode_hint == null:
        return
    selected_mode = "online"
    mode_hint.text = "ONLINE: conecta automaticamente à sala ANDRE3D."
    if not RemoteUpdater.can_play_online():
        mode_hint.text = RemoteUpdater.get_online_block_message()

func _select_character(character: String) -> void:
    selected_character = character

func _select_map_region(index: int) -> void:
    var ids := ["industrial", "center"]
    if index >= 0 and index < ids.size():
        var requested_region: String = String(ids[index])
        var active_region: String = ExternalContent.get_active_region_id()
        if not active_region.is_empty() and active_region != requested_region:
            selected_map_region = active_region
            map_region_option.select(ids.find(active_region))
            if mode_hint != null:
                mode_hint.text = "O mapa %s já está carregado. Feche e reabra o jogo para trocar." % active_region.to_upper()
            _map_content_ready = true
            _sync_download_gate()
            return
        selected_map_region = requested_region
        if _remote_update_ready:
            call_deferred("_prepare_selected_map")

func _prepare_selected_map() -> void:
    if _map_region_loading or not _remote_update_ready or RemoteUpdater.is_client_update_required():
        return
    var requested_region: String = selected_map_region
    if ExternalContent.is_region_available(requested_region):
        _map_content_ready = true
        _sync_download_gate()
        return
    _map_region_loading = true
    _map_content_ready = false
    _sync_download_gate()
    if _download_overlay != null:
        _download_overlay.visible = true
    if mode_hint != null:
        mode_hint.text = "Baixando mapa %s (%s)..." % [requested_region.to_upper(), RemoteUpdater.map_region_size_text(requested_region)]
    var downloaded: bool = await RemoteUpdater.download_map_region(requested_region)
    _map_content_ready = downloaded and ExternalContent.is_region_available(requested_region)
    _map_region_loading = false
    if requested_region != selected_map_region:
        _map_content_ready = ExternalContent.is_region_available(selected_map_region)
        _sync_download_gate()
        call_deferred("_prepare_selected_map")
        return
    _sync_download_gate()
    if mode_hint != null and not _map_content_ready:
        mode_hint.text = "Não foi possível preparar o mapa selecionado. Tente novamente."

func _start_game() -> void:
    if _loading or not _remote_update_ready:
        return
    if RemoteUpdater.is_client_update_required():
        mode_hint.text = RemoteUpdater.get_client_update_message()
        _refresh_update_action()
        return
    if not _map_content_ready:
        await _prepare_selected_map()
        if not _map_content_ready:
            return
    if selected_mode == "online" and not RemoteUpdater.can_play_online():
        mode_hint.text = RemoteUpdater.get_online_block_message()
        return
    start_button.disabled = true
    if selected_mode == "online":
        var voice_permission_granted := await VoiceChat.request_microphone_permission()
        if not voice_permission_granted:
            mode_hint.text = "Permita o acesso ao microfone para usar o chat de voz."
            start_button.disabled = false
            return
    if not ExternalContent.ensure_region(selected_map_region):
        mode_hint.text = ExternalContent.get_status_message()
        start_button.disabled = false
        return
    var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({
            "mode": selected_mode,
            "character": selected_character,
            "map_region": selected_map_region,
        }))
    _show_loading_screen()
    var request_error := ResourceLoader.load_threaded_request(GAME_SCENE, "PackedScene", true)
    if request_error != OK and request_error != ERR_BUSY:
        _loading_failed("Não foi possível iniciar o carregamento.")
        return
    _loading = true
    set_process(true)

func _show_loading_screen() -> void:
    if _loading_overlay != null:
        return
    _loading_overlay = Control.new()
    _loading_overlay.name = "LoadingScreen"
    _loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _loading_overlay.z_index = 100
    add_child(_loading_overlay)

    var image := TextureRect.new()
    image.texture = load(LOADING_ART_PATH) as Texture2D
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _loading_overlay.add_child(image)

    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.03, 0.05, 0.42)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _loading_overlay.add_child(shade)

    var bottom := VBoxContainer.new()
    bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    bottom.position = Vector2(-300, -160)
    bottom.size = Vector2(600, 130)
    bottom.add_theme_constant_override("separation", 10)
    _loading_overlay.add_child(bottom)

    var title := Label.new()
    title.text = "CARREGANDO A CIDADE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    title.add_theme_color_override("font_color", Color.WHITE)
    bottom.add_child(title)
    RemoteUIConfig.register_element("menu.loading_title", title)

    _loading_status = Label.new()
    _loading_status.text = "Preparando o mapa..."
    _loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _loading_status.add_theme_font_size_override("font_size", 16)
    _loading_status.add_theme_color_override("font_color", Color("f6d58a"))
    bottom.add_child(_loading_status)
    RemoteUIConfig.register_element("menu.loading_status", _loading_status)

    _loading_progress = ProgressBar.new()
    _loading_progress.custom_minimum_size = Vector2(0, 24)
    _loading_progress.max_value = 100.0
    _loading_progress.show_percentage = false
    bottom.add_child(_loading_progress)
    RemoteUIConfig.register_element("menu.loading_progress", _loading_progress)

    _loading_percent = Label.new()
    _loading_percent.text = "0%"
    _loading_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _loading_percent.add_theme_font_size_override("font_size", 20)
    _loading_percent.add_theme_color_override("font_color", Color.WHITE)
    bottom.add_child(_loading_percent)
    RemoteUIConfig.register_element("menu.loading_percent", _loading_percent)

func _set_loading_progress(value: float) -> void:
    var percent := int(round(value * 100.0))
    if _loading_progress != null:
        _loading_progress.value = percent
    if _loading_percent != null:
        _loading_percent.text = "%d%%" % percent

func _loading_failed(message: String) -> void:
    _loading = false
    if _loading_status != null:
        _loading_status.text = message
    if start_button != null:
        start_button.disabled = false

extends SceneTree

func _initialize() -> void:
    call_deferred("_run_test")

func _run_test() -> void:
    var remote_ui := root.get_node("RemoteUIConfig")
    var label := Label.new()
    root.add_child(label)
    remote_ui.register_element("menu.subtitle", label)
    var test_config := {
        "schema_version": 1,
        "revision": "runtime-test",
        "elements": {
            "menu.subtitle": {
                "visible": false,
                "text": "Título remoto",
                "font_size": 200,
                "position": [9000, -9000],
                "scale": 8.0,
                "text_color": "inválida"
            },
            "menu.start_button": {"visible": false},
            "nao.registrado": {"text": "ignorar"}
        }
    }
    remote_ui.call("_load_config_text", JSON.stringify(test_config), "test")
    assert(label.text == "Título remoto")
    assert(not label.visible)
    assert(label.position == Vector2(4096.0, -4096.0))
    assert(label.scale == Vector2(2.0, 2.0))
    assert(label.get_theme_font_size("font_size") == 72)
    assert(remote_ui.resolve_visibility("menu.start_button", true))
    label.queue_free()
    print("[remote-ui-config] JSON aplicado; valores limitados; controles essenciais protegidos")
    quit()

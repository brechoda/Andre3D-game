@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name: String = "BackgroundUpdate"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var variant: String = "debug" if debug else "release"
		var filename: String = _plugin_name + ("-debug.aar" if debug else "-release.aar")
		var aar_path: String = "res://addons/" + _plugin_name + "/bin/" + variant + "/" + filename
		# O AAR nativo é opcional no checkout-fonte. O atualizador Godot em
		# primeiro plano continua funcionando sem o serviço nativo em segundo plano.
		return PackedStringArray([aar_path]) if FileAccess.file_exists(aar_path) else PackedStringArray([])

	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([])

	func _get_name() -> String:
		return _plugin_name

@tool
extends EditorPlugin
## Registers the two 16-bit PNG importers (Image and Texture). Pick one per file in the Import
## dock's "Import As" menu; Godot's own texture importer stays the default for PNGs.

const ImportPlugin := preload("res://addons/png16_import/png16_import_plugin.gd")

var _importers: Array[EditorImportPlugin] = []


func _enter_tree() -> void:
	for as_texture: bool in [false, true]:
		var importer: EditorImportPlugin = ImportPlugin.new(as_texture)
		add_import_plugin(importer)
		_importers.append(importer)


func _exit_tree() -> void:
	for importer: EditorImportPlugin in _importers:
		remove_import_plugin(importer)
	_importers.clear()

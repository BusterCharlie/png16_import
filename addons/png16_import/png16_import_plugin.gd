@tool
extends EditorImportPlugin
## Imports a 16-bit PNG at full precision as a FORMAT_RF Image or ImageTexture (.res).
## Values are the first channel: raw (0–65535) or normalised (0–1), times a scale.
## 8-bit PNGs can be let through as 0–1 floats (option allow_8bit).

const PRIORITY: float = 0.1  # below Godot's texture importer, so PNGs default to it

var _as_texture: bool = false


func _init(as_texture: bool = false) -> void:
	_as_texture = as_texture


func _get_importer_name() -> String:
	return "png16.texture" if _as_texture else "png16.image"


func _get_visible_name() -> String:
	return "16-bit PNG as Texture (float)" if _as_texture else "16-bit PNG as Image (float)"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["png"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "ImageTexture" if _as_texture else "Image"


func _get_priority() -> float:
	return PRIORITY


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	# normalized: on gives value / 65535 (0–1), off the raw value (0–65535).
	# scale: multiplies every value afterwards (e.g. metres per step, 0.00625 for Overgrowth).
	# allow_8bit: import 8-bit PNGs too (0–1, or 0–255 when not normalised) instead of failing.
	return [
		{"name": "normalized", "default_value": true},
		{"name": "scale", "default_value": 1.0, "property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "-1000000,1000000,0.000001,or_less,or_greater"},
		{"name": "allow_8bit", "default_value": false},
	]


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _can_import_threaded() -> bool:
	return false


func _import(source_file: String, save_path: String, options: Dictionary,
		_platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var resource: Resource = build_resource(source_file, options, _as_texture)
	if resource == null:
		return ERR_FILE_UNRECOGNIZED
	return ResourceSaver.save(resource, "%s.%s" % [save_path, _get_save_extension()])


## The imported resource (Image, or ImageTexture when as_texture) for the given options, or null.
## Static so it can be used and checked outside the editor.
static func build_resource(source_file: String, options: Dictionary, as_texture: bool) -> Resource:
	var normalized: bool = options.get("normalized", true)
	var scale: float = options.get("scale", 1.0)
	var image: Image = null
	var result: Png16BitLoader.LoadResult = Png16BitLoader.load_16bit_png(source_file)
	if result.success:
		image = Png16BitLoader.to_rf_image(result, normalized, scale)
	elif options.get("allow_8bit", false):
		image = _load_8bit(source_file, normalized, scale)
	if image == null:
		push_error("16-bit PNG import: %s (%s)" % [result.error_message, source_file])
		return null
	return ImageTexture.create_from_image(image) if as_texture else image


## 8-bit fallback: Godot's loader, first channel, as 0–1 (or 0–255) floats.
static func _load_8bit(path: String, normalized: bool, scale: float) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		return null
	image.convert(Image.FORMAT_RF)
	var factor: float = (1.0 if normalized else 255.0) * scale
	if factor != 1.0:
		var values: PackedFloat32Array = image.get_data().to_float32_array()
		for i in values.size():
			values[i] *= factor
		image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RF, values.to_byte_array())
	return image

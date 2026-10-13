extends Control
## Example: loads the same 16-bit heightmap with Godot's own loader and with Png16BitLoader, and
## shows a narrow slice of its height range stretched to full contrast. Godot's 8-bit copy shows
## steps; the 16-bit copy stays smooth. Run this scene (F6).

const HEIGHTMAP: String = "res://addons/png16_import/example/example_height.png"
const SLICE: float = 1.0 / 48.0  # share of the height range stretched to full contrast


func _ready() -> void:
	# Png16BitLoader reads the PNG file itself, so it must be exported as is:
	# example_height.png.import uses the "Keep File (exported as is)" importer.
	var full: Image = Png16BitLoader.load_image(HEIGHTMAP, true)
	var godot := Image.new()
	if full == null or godot.load_png_from_buffer(FileAccess.get_file_as_bytes(HEIGHTMAP)) != OK:
		push_error("Example: could not load " + HEIGHTMAP)
		return
	godot.convert(Image.FORMAT_RF)

	var raw: Image = Png16BitLoader.load_image(HEIGHTMAP, false)
	var raw_values: PackedFloat32Array = raw.get_data().to_float32_array()
	var centre: float = full.get_pixel(full.get_width() / 2, full.get_height() / 2).r

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	row.add_child(_panel("Godot's loader: %d levels" % _count_levels(godot.get_data().to_float32_array()),
		_stretched(godot, centre)))
	row.add_child(_panel("Png16BitLoader: %d levels, raw %d..%d" % [
		_count_levels(raw_values), _min(raw_values), _max(raw_values)], _stretched(full, centre)))


## The heights within SLICE / 2 of `centre`, stretched to 0–1 for display.
func _stretched(heights: Image, centre: float) -> ImageTexture:
	var values: PackedFloat32Array = heights.get_data().to_float32_array()
	for i in values.size():
		values[i] = clampf((values[i] - centre) / SLICE + 0.5, 0.0, 1.0)
	var img := Image.create_from_data(heights.get_width(), heights.get_height(), false, Image.FORMAT_RF, values.to_byte_array())
	img.convert(Image.FORMAT_L8)
	return ImageTexture.create_from_image(img)


func _panel(title: String, texture: Texture2D) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(rect)
	return box


static func _count_levels(values: PackedFloat32Array) -> int:
	var seen: Dictionary = {}
	for v: float in values:
		seen[v] = true
	return seen.size()


static func _min(values: PackedFloat32Array) -> int:
	var m: float = INF
	for v: float in values:
		m = minf(m, v)
	return int(m)


static func _max(values: PackedFloat32Array) -> int:
	var m: float = -INF
	for v: float in values:
		m = maxf(m, v)
	return int(m)

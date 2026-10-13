@tool
class_name Png16BitLoader
extends RefCounted
## Standalone 16-bit PNG loader that preserves full precision (part of addons/png16_import, which
## needs nothing else; the editor import plugin there uses it too).
## Godot's built-in Image.load() converts 16-bit PNGs to 8-bit, losing precision.
##
## load_image() gives a FORMAT_RF Image (raw 0–65535 values or 0–1); load_16bit_png() gives the raw
## big-endian bytes. Both work in exported games.
##
## Fast path (16-bit grayscale, not interlaced): the file is handed to Godot's own PNG decoder
## with its header relabelled as 8-bit gray+alpha. Both layouts have 2 bytes per pixel and the
## same filter step, so libpng undoes the filters and returns each 16-bit sample as its
## [high, low] byte pair, untouched. Only the header is rewritten (and its CRC); the IDAT chunks
## are copied as they are and ancillary chunks (gamma, colour profile) are dropped so libpng
## applies no colour conversion. Works in exported builds (the PNG module is core).
##
## Other 16-bit layouts (RGB, gray+alpha, RGBA) use the script decoder below; interlaced files fail.
## Output in both cases: big-endian 16-bit values, first channel only, 2 bytes per pixel.
## tests/png16_import/check_png16_decode.gd checks both paths byte for byte.

# PNG file format constants
const PNG_SIGNATURE: PackedByteArray = [137, 80, 78, 71, 13, 10, 26, 10]
const PNG_SIGNATURE_LENGTH: int = 8
const CHUNK_LENGTH_SIZE: int = 4
const CHUNK_TYPE_SIZE: int = 4
const CHUNK_CRC_SIZE: int = 4
const IHDR_DATA_SIZE: int = 13

# PNG chunk type identifiers
const CHUNK_IHDR: String = "IHDR"
const CHUNK_IDAT: String = "IDAT"
const CHUNK_IEND: String = "IEND"

# PNG color type constants
const COLOR_TYPE_GRAYSCALE: int = 0
const COLOR_TYPE_RGB: int = 2
const COLOR_TYPE_GRAY_ALPHA: int = 4

# Bytes per pixel for 16-bit images: grayscale, RGB, gray+alpha, RGBA (palette PNGs are never 16-bit)
const BYTES_PER_PIXEL_GRAYSCALE: int = 2
const BYTES_PER_PIXEL_BY_COLOR_TYPE: Dictionary = {0: 2, 2: 6, 4: 4, 6: 8}

# Bit manipulation constants
const BYTE_MASK: int = 0xFF
const BIT_DEPTH_8: int = 8
const BIT_DEPTH_16: int = 16
const CRC32_POLY: int = 0xEDB88320
const CRC32_MASK: int = 0xFFFFFFFF
const MAX_16BIT: int = 65535


## Result structure for PNG loading operations
class LoadResult:
	var success: bool = false
	var width: int = 0
	var height: int = 0
	var data: PackedByteArray = PackedByteArray()
	var bit_depth: int = 0
	var error_message: String = ""

	static func error(message: String) -> LoadResult:
		var result := LoadResult.new()
		result.success = false
		result.error_message = message
		return result

	static func ok(w: int, h: int, pixel_data: PackedByteArray, bits: int) -> LoadResult:
		var result := LoadResult.new()
		result.success = true
		result.width = w
		result.height = h
		result.data = pixel_data
		result.bit_depth = bits
		return result


## Validates PNG file signature (first 8 bytes).
static func _validate_signature(file_data: PackedByteArray) -> bool:
	if file_data.size() < PNG_SIGNATURE_LENGTH:
		return false
	for i in range(PNG_SIGNATURE_LENGTH):
		if file_data[i] != PNG_SIGNATURE[i]:
			return false
	return true


## Reads a 4-byte big-endian integer from the file data at the given position.
static func _read_uint32_be(file_data: PackedByteArray, pos: int) -> int:
	return (file_data[pos] << 24) | (file_data[pos + 1] << 16) | \
		   (file_data[pos + 2] << 8) | file_data[pos + 3]


static func _append_uint32_be(out: PackedByteArray, value: int) -> void:
	out.append((value >> 24) & BYTE_MASK)
	out.append((value >> 16) & BYTE_MASK)
	out.append((value >> 8) & BYTE_MASK)
	out.append(value & BYTE_MASK)


## Standard PNG/zlib CRC-32 (bitwise; only used on the 17-byte header chunk).
static func _crc32(bytes: PackedByteArray) -> int:
	var crc: int = CRC32_MASK
	for b: int in bytes:
		crc ^= b
		for _bit in 8:
			crc = (crc >> 1) ^ (CRC32_POLY if crc & 1 else 0)
	return crc ^ CRC32_MASK


## Parses PNG chunks and extracts header info and compressed image data.
## Returns: {width, height, bit_depth, color_type, interlace, compressed_data, idat_ranges, success}
## idat_ranges holds [start, end) byte ranges of whole IDAT chunks (length, type, data and CRC).
static func _parse_chunks(file_data: PackedByteArray, want_compressed: bool = true) -> Dictionary:
	var pos: int = PNG_SIGNATURE_LENGTH
	var width: int = 0
	var height: int = 0
	var bit_depth: int = 0
	var color_type: int = 0
	var interlace: int = 0
	var compressed_data: PackedByteArray = PackedByteArray()
	var idat_ranges: Array[Vector2i] = []

	while pos + CHUNK_LENGTH_SIZE + CHUNK_TYPE_SIZE <= file_data.size():
		var chunk_start: int = pos
		var chunk_length := _read_uint32_be(file_data, pos)
		pos += CHUNK_LENGTH_SIZE

		var chunk_type := file_data.slice(pos, pos + CHUNK_TYPE_SIZE).get_string_from_ascii()
		pos += CHUNK_TYPE_SIZE

		if chunk_type == CHUNK_IHDR:
			width = _read_uint32_be(file_data, pos)
			height = _read_uint32_be(file_data, pos + 4)
			bit_depth = file_data[pos + 8]
			color_type = file_data[pos + 9]
			interlace = file_data[pos + 12]
			print_verbose("PNG IHDR: %dx%d, bit_depth=%d, color_type=%d" % \
				[width, height, bit_depth, color_type])

		elif chunk_type == CHUNK_IDAT:
			idat_ranges.append(Vector2i(chunk_start, pos + chunk_length + CHUNK_CRC_SIZE))
			if want_compressed:
				compressed_data.append_array(file_data.slice(pos, pos + chunk_length))

		pos += chunk_length + CHUNK_CRC_SIZE

		if chunk_type == CHUNK_IEND:
			break

	return {
		"width": width,
		"height": height,
		"bit_depth": bit_depth,
		"color_type": color_type,
		"interlace": interlace,
		"compressed_data": compressed_data,
		"idat_ranges": idat_ranges,
		"success": width > 0 and height > 0
	}


## Fast path: decodes a 16-bit grayscale PNG with Godot's PNG decoder (see the header comment).
## Returns [high, low] byte pairs, or an empty array if the engine decode did not give LA8.
static func _decode_with_engine(file_data: PackedByteArray, chunks: Dictionary) -> PackedByteArray:
	var w: int = chunks.width
	var h: int = chunks.height
	var ihdr := PackedByteArray()
	ihdr.append_array(CHUNK_IHDR.to_ascii_buffer())
	_append_uint32_be(ihdr, w)
	_append_uint32_be(ihdr, h)
	# bit depth, colour type, compression, filter method, interlace
	ihdr.append_array(PackedByteArray([BIT_DEPTH_8, COLOR_TYPE_GRAY_ALPHA, 0, 0, 0]))

	var png := PackedByteArray()
	png.append_array(PNG_SIGNATURE)
	_append_uint32_be(png, IHDR_DATA_SIZE)
	png.append_array(ihdr)
	_append_uint32_be(png, _crc32(ihdr))
	for r: Vector2i in chunks.idat_ranges:
		png.append_array(file_data.slice(r.x, r.y))
	_append_uint32_be(png, 0)
	png.append_array(CHUNK_IEND.to_ascii_buffer())
	_append_uint32_be(png, _crc32(CHUNK_IEND.to_ascii_buffer()))

	var img := Image.new()
	if img.load_png_from_buffer(png) != OK:
		return PackedByteArray()
	if img.get_format() != Image.FORMAT_LA8 or img.get_width() != w or img.get_height() != h:
		return PackedByteArray()
	return img.get_data()


## Script path: inflates and un-filters the scanlines in GDScript, keeping the first channel.
## Slow (seconds per 2048² map); only used for layouts the fast path does not cover.
static func _reconstruct_pixels(
	decompressed: PackedByteArray,
	width: int,
	height: int,
	color_type: int
) -> PackedByteArray:
	var bpp: int = BYTES_PER_PIXEL_BY_COLOR_TYPE.get(color_type, 0)
	if bpp == 0:
		return PackedByteArray()

	var row_bytes: int = width * bpp
	var scanline_size: int = 1 + row_bytes
	if decompressed.size() < scanline_size * height:
		return PackedByteArray()
	var pixel_data := PackedByteArray()
	if bpp != BYTES_PER_PIXEL_GRAYSCALE:
		pixel_data.resize(width * height * 2)  # 2 bytes per 16-bit value

	var prev := PackedByteArray()
	prev.resize(row_bytes)  # zeros: the row above the first row
	for y in range(height):
		var start: int = y * scanline_size + 1
		var filter_type: int = decompressed[start - 1]
		var cur: PackedByteArray = decompressed.slice(start, start + row_bytes)
		match filter_type:
			1:  # Sub
				for i in range(bpp, row_bytes):
					cur[i] = (cur[i] + cur[i - bpp]) & BYTE_MASK
			2:  # Up
				for i in range(row_bytes):
					cur[i] = (cur[i] + prev[i]) & BYTE_MASK
			3:  # Average
				for i in range(bpp):
					cur[i] = (cur[i] + (prev[i] >> 1)) & BYTE_MASK
				for i in range(bpp, row_bytes):
					cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & BYTE_MASK
			4:  # Paeth
				for i in range(bpp):
					cur[i] = (cur[i] + prev[i]) & BYTE_MASK
				for i in range(bpp, row_bytes):
					var a: int = cur[i - bpp]
					var b: int = prev[i]
					var c: int = prev[i - bpp]
					var pa: int = absi(b - c)
					var pb: int = absi(a - c)
					var pc: int = absi(a + b - c - c)
					var pred: int = c
					if pa <= pb and pa <= pc:
						pred = a
					elif pb <= pc:
						pred = b
					cur[i] = (cur[i] + pred) & BYTE_MASK
		if bpp == BYTES_PER_PIXEL_GRAYSCALE:
			pixel_data.append_array(cur)
		else:
			var dst: int = y * width * 2
			for x in range(width):
				pixel_data[dst + x * 2] = cur[x * bpp]
				pixel_data[dst + x * 2 + 1] = cur[x * bpp + 1]
		prev = cur

	return pixel_data


## Loads a 16-bit PNG heightmap, preserving full precision.
## Returns a LoadResult with width, height, and raw 16-bit pixel data.
## force_script_path skips the engine decoder (used by the decode check).
static func load_16bit_png(path: String, force_script_path: bool = false) -> LoadResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return LoadResult.error("Failed to open file: " + path)

	var file_data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	if not _validate_signature(file_data):
		return LoadResult.error("Not a valid PNG file")

	var chunks := _parse_chunks(file_data, false)
	if not chunks.success:
		return LoadResult.error("Failed to parse PNG chunks")

	if chunks.bit_depth != BIT_DEPTH_16:
		return LoadResult.error("Expected 16-bit PNG, got %d-bit" % chunks.bit_depth)

	if not force_script_path and chunks.color_type == COLOR_TYPE_GRAYSCALE and chunks.interlace == 0:
		var fast: PackedByteArray = _decode_with_engine(file_data, chunks)
		if fast.size() == chunks.width * chunks.height * 2:
			return LoadResult.ok(chunks.width, chunks.height, fast, chunks.bit_depth)
		print_verbose("Png16BitLoader: engine decode failed, using the script decoder: " + path)

	if chunks.interlace != 0:
		return LoadResult.error("Interlaced 16-bit PNGs are not supported")

	chunks = _parse_chunks(file_data, true)
	var decompressed: PackedByteArray = chunks.compressed_data.decompress_dynamic(
		-1, FileAccess.COMPRESSION_DEFLATE
	)
	if decompressed.is_empty():
		return LoadResult.error("Failed to decompress PNG data")

	print_verbose("Decompressed data size: %d bytes" % decompressed.size())

	var pixel_data := _reconstruct_pixels(
		decompressed, chunks.width, chunks.height, chunks.color_type
	)
	if pixel_data.is_empty():
		return LoadResult.error("PNG image data is truncated or the colour type is unsupported")

	return LoadResult.ok(chunks.width, chunks.height, pixel_data, chunks.bit_depth)


## Convenience function returning a Dictionary (for backward compatibility).
## Returns: {width: int, height: int, data: PackedByteArray, bit_depth: int, success: bool}
static func load_16bit_png_dict(path: String) -> Dictionary:
	var result := load_16bit_png(path)
	return {
		"success": result.success,
		"width": result.width,
		"height": result.height,
		"data": result.data,
		"bit_depth": result.bit_depth
	}


## Loads a 16-bit PNG as a FORMAT_RF Image holding the first channel: the raw value (0–65535,
## exact in a 32-bit float) or, with normalized, value / 65535; either times scale.
## Returns null (and reports why) on failure.
static func load_image(path: String, normalized: bool = true, scale: float = 1.0) -> Image:
	var result := load_16bit_png(path)
	if not result.success:
		push_error("Png16BitLoader: %s (%s)" % [result.error_message, path])
		return null
	return to_rf_image(result, normalized, scale)


## Converts a load_16bit_png() result to a FORMAT_RF Image (see load_image).
## One table read per pixel: decode_u16 reads each big-endian pair byte-swapped, and the table is
## indexed by that swapped value.
static func to_rf_image(result: LoadResult, normalized: bool = true, scale: float = 1.0) -> Image:
	var count: int = result.width * result.height
	var by_swapped := PackedFloat32Array()
	by_swapped.resize(MAX_16BIT + 1)
	for swapped in MAX_16BIT + 1:
		var value: float = float(((swapped & BYTE_MASK) << 8) | (swapped >> 8))
		by_swapped[swapped] = (value / MAX_16BIT if normalized else value) * scale
	var values := PackedFloat32Array()
	values.resize(count)
	var data: PackedByteArray = result.data
	for i in count:
		values[i] = by_swapped[data.decode_u16(i * 2)]
	return Image.create_from_data(result.width, result.height, false, Image.FORMAT_RF, values.to_byte_array())

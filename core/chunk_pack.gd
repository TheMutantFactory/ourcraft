class_name ChunkPack
extends RefCounted
## Binary, content-addressed store of compressed chunks (chunks-N.pack).
##
## Layout (little-endian):
##   "OCPK"  u32 version
##   entries: 16-byte hash  u32 length  <length bytes of zstd chunk data>
##
## The hash is the first 16 bytes of SHA-256 over the compressed bytes, so
## identical chunks (copies, forks, repeated colours) are stored once. Saves
## append entries; a truncated final entry from an interrupted append is
## ignored when reading. See docs/file-format.md.

const MAGIC := "OCPK"
const VERSION := 1
const HASH_BYTES := 16
const HEADER_BYTES := 8


## Hex content hash of compressed chunk bytes.
static func hash_of(packed: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(packed)
	return ctx.finish().slice(0, HASH_BYTES).hex_encode()


## Reads a pack into {hash: PackedByteArray}. Returns null if the file is
## missing or isn't a pack.
static func read(path: String):
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < HEADER_BYTES or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return null
	if bytes.decode_u32(4) > VERSION:
		push_error("Chunk pack %s was written by a newer Ourcraft" % path)
		return null
	var out := {}
	var pos := HEADER_BYTES
	var size := bytes.size()
	while pos + HASH_BYTES + 4 <= size:
		var h := bytes.slice(pos, pos + HASH_BYTES).hex_encode()
		var length := bytes.decode_u32(pos + HASH_BYTES)
		var start := pos + HASH_BYTES + 4
		if start + length > size:
			break # interrupted append; everything before it is intact
		out[h] = bytes.slice(start, start + length)
		pos = start + length
	return out


## Writes a complete pack (via a temp file and rename).
static func write(path: String, entries: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	_store_header(f)
	var hashes := entries.keys()
	hashes.sort()
	for h in hashes:
		_store_entry(f, h, entries[h])
	f.close()
	return DirAccess.rename_absolute(tmp, path)


## Appends entries to an existing pack (creating it if needed).
static func append(path: String, entries: Dictionary) -> Error:
	if entries.is_empty() and FileAccess.file_exists(path):
		return OK
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			_store_header(f)
	if f == null:
		return FileAccess.get_open_error()
	var hashes := entries.keys()
	hashes.sort()
	for h in hashes:
		_store_entry(f, h, entries[h])
	f.close()
	return OK


static func entry_size(packed: PackedByteArray) -> int:
	return HASH_BYTES + 4 + packed.size()


static func _store_header(f: FileAccess) -> void:
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(VERSION)


static func _store_entry(f: FileAccess, h: String, packed: PackedByteArray) -> void:
	f.store_buffer(h.hex_decode())
	f.store_32(packed.size())
	f.store_buffer(packed)

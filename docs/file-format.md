# Ourcraft project format (version 2)

A project is a folder, normally named `<title>.ourcraft`:

```text
world.ourcraft/
├── manifest.json     project settings
├── objects.json      every object's metadata, one line per object
└── chunks-N.pack     compressed voxel chunks, stored by content hash
```

Everything except the chunk pack is plain JSON, so the folder diffs well in
Git: editing one object changes one line of `objects.json` and appends to the
pack.

## manifest.json

```json
{
  "format": "ourcraft.project",
  "version": 2,
  "engine": "godot-4.7-stable (official)",
  "title": "Small street",
  "units": {"min_block_m": 0.01, "up": "+y", "handedness": "right"},
  "root": "3ffede8d425b4311",
  "palette": ["8a8f98", "f2efe6", "..."],
  "objects_file": "objects.json"
}
```

- `units.min_block_m` is the size of the smallest block in metres. All
  integer coordinates count these units.
- `root` is the id of the object that forms the world.
- `palette` lists the colours, as hex. A cell value `n` (1–255) uses entry
  `n - 1`; 0 is empty.

## objects.json

The first line is a header that names the chunk pack. Then comes one object
per line, sorted by id, and the file ends with `]}`. The whole file is also
valid JSON.

```text
{"chunks_file": "chunks-1.pack", "format": "ourcraft.objects", "version": 1, "objects": [
{"children": [], "chunks": [{"count": 1100, "hash": "9c2e…", "key": [0, 0, 0]}], "id": "…", "name": "Crate", "unit": 1},
...
]}
```

Each object has:

| Field | Meaning |
|---|---|
| `id` | Stable random id (16 hex digits). |
| `name` | Display name. |
| `unit` | Block size of this object, in multiples of the smallest block. |
| `chunks` | `key` (chunk coordinates), `hash` (content hash in the pack) and `count` (solid cells), sorted by z, then y, then x. |
| `children` | Instances: `id`, `object` (the placed object's id), `offset` (in smallest-block units of this object's space) and `rot` (quarter turns about +Y). |
| `forked_from` | Optional id of the object this one was copied from. |

Keys within each line are sorted, so saving the same project twice produces
the same bytes. If the file has been reformatted by hand, it is read as
ordinary JSON and rewritten in this layout on the next save.

## chunks-N.pack

A chunk is 32 × 32 × 32 cells, one byte per cell (palette index, 0 = empty),
indexed `x + y·32 + z·1024`, stored zstd-compressed.

The pack is little-endian binary:

```text
"OCPK"   u32 version (1)
repeat:  16-byte hash   u32 length   <length bytes of zstd data>
```

- **Hash:** the first 16 bytes of SHA-256 over the compressed bytes.
  Identical chunks are stored once, however many objects use them.
- **Appending:** saves only add chunks the pack doesn't have yet. If a save is
  interrupted mid-append, readers ignore the incomplete last entry.
- **Compaction:** when more than half the pack is no longer referenced, the
  next save writes the live chunks to a new `chunks-(N+1).pack` and deletes
  the old one after `objects.json` points at the new file.
- **Commit point:** `objects.json` names the pack and is replaced atomically
  (write to a temp file, then rename). A crash at any point leaves a
  consistent project: either the previous `objects.json` with a pack that
  still contains its chunks, or the new one.

Stored `count`s let a loader skip decompression. Ourcraft checks each chunk's
size the first time it decompresses it.

## Other files

- **Version 1 folders** (`objects/<id>.json`, one file per object, chunks
  base64-encoded inside) still load. The next save converts them to version
  2 and removes the `objects/` folder.
- **Object bundles** (`*.ourobj.json`, from Export…) are a single JSON file
  holding an object and everything nested in it, with chunks base64-encoded
  inline (`chunk_format: u8-zstd-base64`; older bundles used
  `u8-deflate-base64`).

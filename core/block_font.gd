class_name BlockFont
extends RefCounted
## A 5×7 capital-letter pixel font for writing words in voxels. Lowercase is
## drawn as capitals; characters without a glyph are drawn as "?".

const WIDTH := 5
const HEIGHT := 7
## Pixels between letters.
const SPACING := 1

const GLYPHS := {
	"A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
	"B": "####.|#...#|#...#|####.|#...#|#...#|####.",
	"C": ".###.|#...#|#....|#....|#....|#...#|.###.",
	"D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
	"E": "#####|#....|#....|####.|#....|#....|#####",
	"F": "#####|#....|#....|####.|#....|#....|#....",
	"G": ".###.|#...#|#....|#.###|#...#|#...#|.####",
	"H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
	"I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.",
	"J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
	"K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
	"L": "#....|#....|#....|#....|#....|#....|#####",
	"M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
	"N": "#...#|#...#|##..#|#.#.#|#..##|#...#|#...#",
	"O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
	"P": "####.|#...#|#...#|####.|#....|#....|#....",
	"Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
	"R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
	"S": ".####|#....|#....|.###.|....#|....#|####.",
	"T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
	"U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
	"V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
	"W": "#...#|#...#|#...#|#.#.#|#.#.#|#.#.#|.#.#.",
	"X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
	"Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
	"Z": "#####|....#|...#.|..#..|.#...|#....|#####",
	"0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
	"1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
	"2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
	"3": "####.|....#|....#|.###.|....#|....#|####.",
	"4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
	"5": "#####|#....|####.|....#|....#|#...#|.###.",
	"6": "..##.|.#...|#....|####.|#...#|#...#|.###.",
	"7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
	"8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
	"9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
	"-": ".....|.....|.....|.###.|.....|.....|.....",
	"'": "..#..|..#..|.#...|.....|.....|.....|.....",
	"/": "....#|....#|...#.|..#..|.#...|#....|#....",
	".": ".....|.....|.....|.....|.....|.....|..#..",
	"?": ".###.|#...#|....#|...#.|..#..|.....|..#..",
	" ": ".....|.....|.....|.....|.....|.....|.....",
}


## Width of a text in pixels.
static func text_width(text: String) -> int:
	if text.is_empty():
		return 0
	return text.length() * (WIDTH + SPACING) - SPACING


## Calls draw(x, y) for every lit pixel; y = 0 is the bottom row.
static func each_pixel(text: String, draw: Callable) -> void:
	var up := text.to_upper()
	for i in up.length():
		var glyph: String = GLYPHS.get(up[i], GLYPHS["?"])
		var rows := glyph.split("|")
		var x0 := i * (WIDTH + SPACING)
		for r in HEIGHT:
			var row: String = rows[r]
			for c in WIDTH:
				if row[c] == "#":
					draw.call(x0 + c, HEIGHT - 1 - r)


## Writes text into a grid: letters in the XY plane starting at the origin,
## depth cells thick along +Z.
static func write(grid: VoxelGrid, text: String, color: int, depth := 2) -> void:
	# Build raw chunks first: one compression per chunk instead of one per
	# pixel.
	var raw := {}
	each_pixel(text, func(x: int, y: int) -> void:
		for z in depth:
			var p := Vector3i(x, y, z)
			var key := VoxelGrid.chunk_of(p)
			var data: PackedByteArray = raw.get(key, PackedByteArray())
			if data.is_empty():
				data.resize(VoxelGrid.VOLUME)
				raw[key] = data
			data[VoxelGrid.index(p.x & VoxelGrid.MASK, p.y & VoxelGrid.MASK, p.z & VoxelGrid.MASK)] = color)
	for key in raw:
		grid.set_chunk(key, raw[key])

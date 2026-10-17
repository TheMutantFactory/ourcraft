class_name PaletteRamps
extends RefCounted
## Colour gradients appended to a project's palette, so words can be written
## with each letter a step along a ramp. Palette entries are bytes, so the
## ramps are a fixed set rather than arbitrary colours.

const STEPS := 8
const RAMPS := [
	[Color("#ff5f6d"), Color("#ffc371")], # coral -> peach
	[Color("#36d1dc"), Color("#5b86e5")], # aqua -> blue
	[Color("#a8e063"), Color("#2f8f3a")], # lime -> green
	[Color("#f7971e"), Color("#ffd200")], # orange -> yellow
	[Color("#c471f5"), Color("#4a00e0")], # violet -> indigo
	[Color("#ff9a9e"), Color("#fad0c4")], # pink -> blush
	[Color("#00c9ff"), Color("#92fe9d")], # sky -> mint
	[Color("#fc5c7d"), Color("#6a82fb")], # rose -> periwinkle
]


## Makes sure the ramps are in the palette and returns the palette value
## (1-based) of the first ramp's first step.
static func ensure(project: Project) -> int:
	var base := 11
	var needed := base - 1 + RAMPS.size() * STEPS
	if project.palette.size() >= needed and project.palette[base - 1].is_equal_approx(RAMPS[0][0]):
		return base
	while project.palette.size() < base - 1:
		project.palette.append(Color.GRAY)
	project.palette.resize(base - 1)
	for r in RAMPS:
		for s in STEPS:
			project.palette.append(r[0].lerp(r[1], float(s) / (STEPS - 1)))
	return base


## Palette values for each letter of a word of `length` letters, spread
## along ramp `ramp`.
static func letter_colours(base: int, ramp: int, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	for i in length:
		var t := 0.0 if length <= 1 else float(i) / (length - 1)
		out.append(base + (ramp % RAMPS.size()) * STEPS + roundi(t * (STEPS - 1)))
	return out

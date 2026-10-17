class_name Settings
extends RefCounted
## User preferences stored in user://settings.cfg.

const PATH := "user://settings.cfg"
const DEFAULT_MIN_BLOCK_M := 0.01


static func min_block_m() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return DEFAULT_MIN_BLOCK_M
	return float(cfg.get_value("world", "min_block_m", DEFAULT_MIN_BLOCK_M))


static func set_min_block_m(value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("world", "min_block_m", value)
	cfg.save(PATH)


## Interface scale (Window.content_scale_factor). Defaults to twice the
## screen's own scale, e.g. 4 on a Retina display.
static func ui_scale() -> float:
	var cfg := ConfigFile.new()
	var fallback := 2.0 * DisplayServer.screen_get_scale()
	if cfg.load(PATH) != OK:
		return fallback
	return float(cfg.get_value("interface", "scale", fallback))


static func set_ui_scale(value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("interface", "scale", value)
	cfg.save(PATH)

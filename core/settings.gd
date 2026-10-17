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

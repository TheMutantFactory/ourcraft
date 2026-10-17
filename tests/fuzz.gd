extends SceneTree
## Runs TreeFuzz over many seeds. tools/fuzz.sh [--seeds=N] [--steps=M]
## [--seed=S] [--no-view] [--verbose]. Exits non-zero if any check failed.

var _ran := false


## Runs on the first frame, so nodes added to the tree (the WorldView) are
## ready.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return false


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var steps := int(args.get("steps", "300"))
	var seeds := []
	if args.has("seed"):
		seeds = [int(args.seed)]
	else:
		for s in int(args.get("seeds", "20")):
			seeds.append(s + 1)
	var use_view := not args.has("no-view")
	var base := ProjectSettings.globalize_path("user://fuzz")
	DirAccess.make_dir_recursive_absolute(base)
	var failed := 0
	var totals := {}
	var t0 := Time.get_ticks_msec()
	for seed in seeds:
		var f := TreeFuzz.new(seed)
		f.save_dir = base.path_join("seed-%d.ourcraft" % seed)
		TreeFuzz._clear_dir(f.save_dir)
		var view: WorldView = null
		if use_view:
			view = WorldView.new()
			root.add_child(view)
			view.set_project(f.p)
			f.view = view
		for i in steps:
			if not f.step():
				break
			if i % 25 == 24:
				f.check_view()
			if i % 50 == 49:
				f.check_save_load(base.path_join("fresh.ourcraft"))
				f.check_bundle(base.path_join("bundle.ourobj.json"))
			if not f.failures.is_empty():
				break
		if view != null:
			view.free()
		for k in f.stats:
			totals[k] = int(totals.get(k, 0)) + f.stats[k]
		if f.failures.is_empty():
			if args.has("verbose"):
				print("seed %d: ok (%d steps, %d objects)" % [seed, f.steps, f.p.defs.size()])
		else:
			failed += 1
			print("seed %d FAILED: %s" % [seed, f.failures[0]])
			for line in f.history.slice(maxi(0, f.history.size() - 12)):
				print("    " + line)
	print("%d seeds x %d steps, %d failed, %.1f s" % [seeds.size(), steps, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	print("operations: %s" % totals)
	quit(1 if failed > 0 else 0)

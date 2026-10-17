class_name Scenario
extends Node
## Base for watchable soak scenarios (tools/hole.sh, tools/burst.sh). A
## scenario drives a project through the normal Project API while you watch;
## with --soak=<seconds> it runs unattended, then checks the project and the
## view, prints a report and quits (exit code 1 if anything failed).
##
## Subclasses implement _setup(), _tick(dt), optionally _poke(dt) (soak-only
## provocations whose outcomes they check, adding to poke_failures),
## status_lines() and report_line().

var main: Node
var project: Project
var view: WorldView
var rng := RandomNumberGenerator.new()
var stats := {}
var soak := 0.0
var poke_failures := PackedStringArray()
var _elapsed := 0.0
var _start_ram := 0


func _init(seed := 1) -> void:
	rng.seed = seed


## Starts on a project (also called when the game switches projects).
## Undo is turned off: a simulation's changes would flood the history.
func attach(main_node: Node, p: Project, v: WorldView) -> void:
	main = main_node
	project = p
	view = v
	project.set_recording(false)
	_setup()


func _setup() -> void:
	pass


func _tick(_dt: float) -> void:
	pass


func _poke(_dt: float) -> void:
	pass


## Extra HUD lines.
func status_lines() -> String:
	return ""


## One line for the soak report.
func report_line() -> String:
	return ""


func _physics_process(dt: float) -> void:
	if project == null:
		return
	_elapsed += dt
	if _start_ram == 0:
		_start_ram = OS.get_static_memory_usage()
	if soak > 0.0 and _elapsed >= soak:
		_finish_soak()
		soak = 0.0
		return
	_tick(dt)
	if soak > 0.0:
		_poke(dt)


## Checks the project and the view, prints a report and quits.
func _finish_soak() -> void:
	view.flush()
	var f := TreeFuzz.new(1, project)
	f.view = view
	f._check_invariants()
	f.check_view()
	var orphans := project.defs.size() - project.dependencies(project.root_id).size()
	if orphans > 0:
		f.fail("%d objects are no longer used anywhere (a leak)" % orphans)
	for msg in poke_failures:
		f.fail(msg)
	print("%s soak: %.0f s, %s" % [name, _elapsed, stats])
	print("  library %d objects, %d placements, RAM %+d MB since start, %d fps%s" % [
		project.defs.size(), view._placements.size(),
		(OS.get_static_memory_usage() - _start_ram) / 1_000_000, Engine.get_frames_per_second(),
		("; " + report_line()) if report_line() != "" else ""])
	if f.failures.is_empty():
		print("  all checks passed")
	for msg in f.failures:
		print("  FAILED " + msg)
	get_tree().quit(0 if f.failures.is_empty() else 1)

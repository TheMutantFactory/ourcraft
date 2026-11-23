class_name PalettePanel
extends PanelContainer
## The palette (E): every object in the library as a picture, in tabs.
## Click one to pick it up and place it; right-click to file it under a tab.
##
## This is deliberately a palette, not a browser: no search, tags or
## filters (see docs/one-room-mvp.md §5). Each tab shows at most MAX_PER_TAB
## objects.

signal picked(def_id: String)
signal category_chosen(def_id: String, category: String)

const OTHER := "Other"
const MAX_PER_TAB := 120
const TILE := Vector2(112, 128)
const GAP := 8

var thumbnailer: Thumbnailer

var _tabs: TabBar
var _grid: GridContainer
var _scroll: ScrollContainer
var _footer: Label
var _menu: PopupMenu
var _project: Project
var _edit_def_id := ""
var _groups: Dictionary = {}
var _tab := 0
var _buttons: Dictionary = {} # def_id -> Button
var _menu_def := ""
var _first := true


func _ready() -> void:
	# Proportional anchors, not a fixed size: at the default text scale (4×
	# on Retina) the logical screen can be under 700 points wide.
	anchor_left = 0.06
	anchor_right = 0.94
	anchor_top = 0.1
	anchor_bottom = 0.8
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	visible = false
	resized.connect(_fit_columns)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_tabs = TabBar.new()
	_tabs.clip_tabs = false
	_tabs.tab_changed.connect(func(i):
		_tab = i
		_fill_grid())
	col.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_grid)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	col.add_child(_footer)
	_menu = PopupMenu.new()
	for c in ObjectDef.CATEGORIES + [OTHER]:
		_menu.add_item(c)
	_menu.index_pressed.connect(func(i):
		var c := _menu.get_item_text(i)
		category_chosen.emit(_menu_def, "" if c == OTHER else c))
	add_child(_menu)


## As many tile columns as fit the panel's width.
func _fit_columns() -> void:
	if _grid != null:
		_grid.columns = maxi(2, floori((size.x - 40.0) / (TILE.x + GAP)))


func tab_names() -> Array:
	return ObjectDef.CATEGORIES + [OTHER]


## Objects by tab: {tab name -> [def ids sorted by name]}. The world itself
## isn't listed.
static func group(project: Project) -> Dictionary:
	var out := {}
	for t in ObjectDef.CATEGORIES + [OTHER]:
		out[t] = []
	var defs := project.defs.values()
	defs.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	for def in defs:
		if def.id == project.root_id:
			continue
		var t: String = def.category if ObjectDef.CATEGORIES.has(def.category) else OTHER
		out[t].append(def.id)
	return out


## Rebuilds the tabs and the current tab's tiles. edit_def_id is the object
## being edited: objects that contain it can't be placed in it.
func refresh(project: Project, edit_def_id: String) -> void:
	_project = project
	_edit_def_id = edit_def_id
	_groups = group(project)
	var names := tab_names()
	if _tabs.tab_count != names.size():
		_tabs.clear_tabs()
		for n in names:
			_tabs.add_tab(n)
	for i in names.size():
		var n: int = _groups[names[i]].size()
		_tabs.set_tab_title(i, "%s  %d" % [names[i], n] if n > 0 else names[i])
	if _first:
		_first = false
		# Open on the first tab that has something in it.
		for i in names.size():
			if not _groups[names[i]].is_empty():
				_tab = i
				break
	_tabs.current_tab = _tab
	_fill_grid()


func _fill_grid() -> void:
	for c in _grid.get_children():
		c.free()
	_buttons.clear()
	if _project == null:
		return
	var name: String = tab_names()[_tab]
	var ids: Array = _groups.get(name, [])
	for i in mini(ids.size(), MAX_PER_TAB):
		_grid.add_child(_tile(ids[i]))
	var hint := "Click to place · Right-click to move to another tab · E or Esc to close"
	if ids.is_empty():
		hint = ("Nothing here yet. Right-click an object in another tab to file it under %s." % name) \
			if name != OTHER else "Objects without a tab show up here."
	elif ids.size() > MAX_PER_TAB:
		hint = "Showing %d of %d. %s" % [MAX_PER_TAB, ids.size(), hint]
	_footer.text = hint


func _tile(def_id: String) -> Button:
	var def: ObjectDef = _project.defs[def_id]
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.text = def.name
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = true
	b.add_theme_font_size_override("font_size", 12)
	var size := _project.def_bounds(def_id).size * _project.voxel_size * 100.0
	b.tooltip_text = "%s\n%s × %s × %s cm" % [def.name, Hud._fmt(size.x), Hud._fmt(size.y), Hud._fmt(size.z)]
	if _edit_def_id != "" and _project.would_cycle(_edit_def_id, def_id):
		b.disabled = true
		b.tooltip_text += "\nCan't be placed inside itself"
	if thumbnailer != null:
		var tex := thumbnailer.request(_project, def_id)
		if tex != null:
			b.icon = tex
	b.pressed.connect(func(): picked.emit(def_id))
	b.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_open_menu(def_id, get_global_mouse_position()))
	_buttons[def_id] = b
	return b


func _open_menu(def_id: String, at: Vector2) -> void:
	_menu_def = def_id
	_menu.position = Vector2i(at)
	_menu.reset_size()
	_menu.popup()


## Development hook: opens the tab menu over the i-th tile.
func debug_open_menu(i: int) -> void:
	var b: Control = _grid.get_child(i)
	_open_menu(_buttons.find_key(b), b.get_global_rect().get_center())


## A thumbnail finished rendering: show it if its tile is on screen.
func on_rendered(def_id: String, tex: Texture2D) -> void:
	var b: Button = _buttons.get(def_id)
	if b != null and is_instance_valid(b):
		b.icon = tex


func tile_count() -> int:
	return _grid.get_child_count()


func current_tab_name() -> String:
	return tab_names()[_tab]


func select_tab(name: String) -> void:
	var i := tab_names().find(name)
	if i >= 0:
		_tab = i
		_tabs.current_tab = i
		_fill_grid()

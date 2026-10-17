class_name Hud
extends CanvasLayer
## On-screen interface: crosshair, breadcrumb, hotbar, toasts, help, and the
## side panel (outline, library, settings) shown when the mouse is released.

signal outline_selected(path: PackedStringArray)
signal outline_activated(path: PackedStringArray)
## An outline row was dragged onto another: move it into that object.
signal reparent_requested(path: PackedStringArray, to_path: PackedStringArray)
signal command(name: String)
signal place_object(def_id: String)
signal rename_object(def_id: String, new_name: String)
signal delete_object(def_id: String)
signal export_object(def_id: String, file_path: String)
signal import_object(file_path: String)
signal min_block_changed(cm: float)
signal object_unit_changed(unit: int)
signal ui_scale_changed(value: float)

const UNITS := [1, 2, 5, 10, 25, 50, 100]

var context_label: Label
var selection_label: Label
var brush_label: Label
var toast_label: Label
var help_panel: PanelContainer
var status_label: Label
var hotbar: HBoxContainer
var panel: PanelContainer
var outline: Tree
var library: ItemList
var name_edit: LineEdit
var min_block_spin: SpinBox
var unit_option: OptionButton
var ui_scale_spin: SpinBox
var file_dialog: FileDialog

var _toast_time := 0.0
var _swatches: Array = []
var _lib_ids: Array = []
var _suppress := false
var _dialog_mode := ""
var _outline_project: Project
var _outline_edit := PackedStringArray()
var _outline_selected = null
var _outline_counts: Dictionary = {}


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	cross.add_theme_constant_override("outline_size", 4)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.position -= Vector2(10, 18)
	cross.size = Vector2(20, 36)
	root.add_child(cross)

	var top := VBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 16
	top.offset_top = 14
	top.offset_right = -140
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	context_label = _shadow_label(20)
	top.add_child(context_label)
	selection_label = _shadow_label(16)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.add_theme_color_override("font_color", Color("#ffd75e"))
	top.add_child(selection_label)

	status_label = _shadow_label(13)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(status_label)
	_pin_top_right(status_label, 14, 120)

	help_panel = PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.offset_top = 64
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.visible = false
	root.add_child(help_panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	help_panel.add_child(cols)
	var lines := HELP.split("\n")
	var half := ceili(lines.size() / 2.0)
	for part in [lines.slice(0, half), lines.slice(half)]:
		var l := Label.new()
		l.text = "\n".join(part)
		l.add_theme_font_size_override("font_size", 13)
		cols.add_child(l)

	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_bottom = -12
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	toast_label = _shadow_label(18)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toast_label.clip_text = true
	bottom.add_child(toast_label)
	brush_label = _shadow_label(15)
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brush_label.clip_text = true
	bottom.add_child(brush_label)
	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(bar)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 6)
	bar.add_child(hotbar)

	_build_panel(root)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.ourobj.json ; Ourcraft object"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


const HELP := """WASD move · Space jump · Shift sprint
F fly (Space / Shift up and down)
Left click break · Right click place
Middle click pick colour · 1–0 colour
Scroll brush size · T surface / grid placing
, . shrink / grow yourself
Q select · Q again walk up · Shift+Q walk down
Enter edit · Backspace leave · I isolate · L lines
N new object · G move · R rotate · Del delete · B burst
Ctrl+C copy · Ctrl+V paste · Ctrl+D duplicate
U make unique · Ctrl+Z undo · Ctrl+Shift+Z redo
Ctrl+S save · Ctrl+O reload · Ctrl+ +/− text size
Tab panel · H close this"""


func _pin_top_right(c: Control, top: float, width: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_left = -width - 16
	c.offset_right = -16
	c.offset_top = top
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _shadow_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.12, 0.86)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", sb)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.2, 0.22, 0.27)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(6)
	var hov := btn.duplicate()
	hov.bg_color = Color(0.28, 0.31, 0.38)
	var pr := btn.duplicate()
	pr.bg_color = Color(0.36, 0.42, 0.55)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", pr)
	t.set_stylebox("normal", "OptionButton", btn)
	t.set_stylebox("hover", "OptionButton", hov)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.05, 0.06, 0.07, 0.9)
	field.set_corner_radius_all(6)
	field.set_content_margin_all(6)
	t.set_stylebox("panel", "Tree", field)
	t.set_stylebox("panel", "ItemList", field)
	t.set_stylebox("normal", "LineEdit", field)
	return t


func _build_panel(root: Control) -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.position = Vector2(14, 90)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.size = Vector2(360, 0)
	panel.offset_bottom = -110
	panel.visible = false
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	col.add_child(_heading("Outline"))
	outline = Tree.new()
	outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline.size_flags_stretch_ratio = 1.6
	outline.custom_minimum_size.y = 220
	outline.hide_root = false
	outline.item_selected.connect(_on_outline_selected)
	outline.item_activated.connect(_on_outline_activated)
	outline.item_collapsed.connect(_on_outline_item_collapsed)
	outline.set_drag_forwarding(_outline_get_drag, _outline_can_drop, _outline_drop)
	col.add_child(outline)
	col.add_child(_buttons([["Edit", "edit"], ["Leave", "leave"], ["Isolate", "isolate"]]))
	col.add_child(_buttons([["Move", "grab"], ["Rotate", "rotate"], ["Unique", "unique"], ["Delete", "delete"]]))

	col.add_child(_heading("Library"))
	library = ItemList.new()
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.custom_minimum_size.y = 160
	library.item_selected.connect(_on_library_selected)
	library.item_activated.connect(func(i): place_object.emit(_lib_ids[i]))
	col.add_child(library)
	var name_row := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Object name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t): _rename_selected())
	name_row.add_child(name_edit)
	var rn := Button.new()
	rn.text = "Rename"
	rn.pressed.connect(_rename_selected)
	name_row.add_child(rn)
	col.add_child(name_row)
	var lib_btns := HBoxContainer.new()
	for spec in [["Place", "_place"], ["Export…", "_export"], ["Import…", "_import"], ["Delete", "_delete"]]:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Callable(self, spec[1]))
		lib_btns.add_child(b)
	col.add_child(lib_btns)

	col.add_child(_heading("Settings"))
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	var l1 := Label.new()
	l1.text = "Smallest block (cm)"
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l1)
	min_block_spin = SpinBox.new()
	min_block_spin.min_value = 0.1
	min_block_spin.max_value = 100
	min_block_spin.step = 0.1
	min_block_spin.value_changed.connect(func(v):
		if not _suppress: min_block_changed.emit(v))
	grid.add_child(min_block_spin)
	var l2 := Label.new()
	l2.text = "This object's block size"
	grid.add_child(l2)
	unit_option = OptionButton.new()
	for u in UNITS:
		unit_option.add_item("%d×" % u, u)
	unit_option.item_selected.connect(func(i):
		if not _suppress: object_unit_changed.emit(unit_option.get_item_id(i)))
	grid.add_child(unit_option)
	var l3 := Label.new()
	l3.text = "Text size"
	grid.add_child(l3)
	ui_scale_spin = SpinBox.new()
	ui_scale_spin.min_value = 1.0
	ui_scale_spin.max_value = 8.0
	ui_scale_spin.step = 0.25
	ui_scale_spin.suffix = "×"
	ui_scale_spin.value_changed.connect(func(v):
		if not _suppress: ui_scale_changed.emit(v))
	grid.add_child(ui_scale_spin)
	col.add_child(_buttons([["Save", "save"], ["Reload", "load"], ["New world", "new_world"], ["Demo", "demo"]]))


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	return l


func _buttons(specs: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for spec in specs:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cmd: String = spec[1]
		b.pressed.connect(func(): command.emit(cmd))
		row.add_child(b)
	return row


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		toast_label.modulate.a = clampf(_toast_time, 0.0, 1.0)


func toast(msg: String, seconds := 3.0) -> void:
	toast_label.text = msg
	_toast_time = seconds
	toast_label.modulate.a = 1.0


func set_palette(all_colors: Array, current: int) -> void:
	# The hotbar holds the ten colours on keys 1-0; extra palette entries
	# (gradient ramps) are for generated content.
	var colors := all_colors.slice(0, 10)
	if _swatches.size() != colors.size():
		for c in hotbar.get_children():
			c.free()
		_swatches.clear()
		for i in colors.size():
			var sw := Panel.new()
			sw.custom_minimum_size = Vector2(34, 34)
			var key := Label.new()
			key.text = str((i + 1) % 10)
			key.add_theme_font_size_override("font_size", 11)
			key.add_theme_color_override("font_outline_color", Color.BLACK)
			key.add_theme_constant_override("outline_size", 3)
			key.position = Vector2(4, 1)
			sw.add_child(key)
			hotbar.add_child(sw)
			_swatches.append(sw)
	for i in colors.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[i]
		sb.set_corner_radius_all(6)
		if i + 1 == current:
			sb.border_color = Color.WHITE
			sb.set_border_width_all(3)
		_swatches[i].add_theme_stylebox_override("panel", sb)


func show_panel(on: bool) -> void:
	panel.visible = on
	if on:
		help_panel.visible = false


func panel_open() -> bool:
	return panel.visible


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func set_ui_scale_value(value: float) -> void:
	_suppress = true
	ui_scale_spin.value = value
	_suppress = false


func set_settings(min_block_cm: float, unit: int) -> void:
	_suppress = true
	min_block_spin.value = min_block_cm
	var idx := unit_option.get_item_index(unit)
	if idx < 0:
		unit_option.add_item("%d×" % unit, unit)
		idx = unit_option.get_item_index(unit)
	unit_option.select(idx)
	_suppress = false


# --- Outline ---------------------------------------------------------------

func refresh_outline(project: Project, edit_path: PackedStringArray, selected) -> void:
	_suppress = true
	_outline_project = project
	_outline_edit = edit_path
	_outline_selected = selected
	_outline_counts = project.usage_counts()
	outline.clear()
	_outline_row(outline.create_item(), project.root(), PackedStringArray(), 0)
	var sel := outline.get_selected()
	if sel != null:
		outline.scroll_to_item(sel, true)
	_suppress = false


## Fills one outline row. Children are only created for rows that are open
## (the edited or selected branch, or rows the user expands), so a project
## with thousands of objects doesn't build thousands of rows up front.
func _outline_row(item: TreeItem, def: ObjectDef, path: PackedStringArray, depth: int) -> void:
	var text := def.name
	var uses: int = _outline_counts.get(def.id, 0)
	if uses > 1:
		text += "  ×%d" % uses
	if path == _outline_edit:
		text = "✎ " + text
		item.set_custom_color(0, Color("#7fd3ff"))
	item.set_text(0, text)
	item.set_metadata(0, path)
	if _outline_selected != null and path == _outline_selected:
		item.select(0)
	if def.children.is_empty() or depth >= Project.MAX_DEPTH:
		return
	var open := depth == 0 or _is_prefix(path, _outline_edit) \
			or (_outline_selected != null and _is_prefix(path, _outline_selected))
	if open:
		_outline_children(item, def, path, depth)
	else:
		# Placeholder so the row shows an expand arrow.
		outline.create_item(item).set_text(0, "…")
		item.collapsed = true


func _outline_children(item: TreeItem, def: ObjectDef, path: PackedStringArray, depth: int) -> void:
	for inst in def.children:
		var child_def: ObjectDef = _outline_project.defs.get(inst.def_id)
		if child_def == null:
			continue
		var p := path.duplicate()
		p.append(inst.id)
		_outline_row(outline.create_item(item), child_def, p, depth + 1)


# Dragging a row onto another row moves the dragged object into it.

func _outline_get_drag(at: Vector2) -> Variant:
	var item := outline.get_item_at_position(at)
	if item == null or item.get_metadata(0) == null:
		return null
	var path: PackedStringArray = item.get_metadata(0)
	if path.is_empty():
		return null # the world can't be moved
	outline.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	var preview := Label.new()
	preview.text = "Move " + item.get_text(0).trim_prefix("✎ ")
	outline.set_drag_preview(preview)
	return {"outline_path": path}


func _outline_can_drop(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("outline_path")) or _outline_project == null:
		return false
	var item := outline.get_item_at_position(at)
	if item == null or item.get_metadata(0) == null:
		return false
	return can_move(data.outline_path, item.get_metadata(0))


## Whether the outline row at path may be dropped onto to_path.
func can_move(path: PackedStringArray, to_path: PackedStringArray) -> bool:
	if _outline_project == null or path.is_empty():
		return false
	if to_path == path.slice(0, path.size() - 1) or to_path == path:
		return false
	var inst := _outline_project.instance_at(path)
	var to := _outline_project.def_at(to_path)
	return inst != null and to != null and not _outline_project.would_cycle(to.id, inst.def_id)


func _outline_drop(at: Vector2, data: Variant) -> void:
	outline.drop_mode_flags = Tree.DROP_MODE_DISABLED
	var item := outline.get_item_at_position(at)
	if item != null and item.get_metadata(0) != null:
		reparent_requested.emit(data.outline_path, item.get_metadata(0))


## Expanding a row replaces its placeholder with the real children.
func _on_outline_item_collapsed(item: TreeItem) -> void:
	if item.collapsed or _outline_project == null:
		return
	var first := item.get_first_child()
	if first == null or first.get_metadata(0) != null:
		return
	first.free()
	var path: PackedStringArray = item.get_metadata(0)
	var def := _outline_project.def_at(path)
	if def != null:
		var was := _suppress
		_suppress = true
		_outline_children(item, def, path, path.size())
		_suppress = was


static func _is_prefix(a: PackedStringArray, b: PackedStringArray) -> bool:
	if a.size() > b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _on_outline_selected() -> void:
	if _suppress:
		return
	var item := outline.get_selected()
	if item != null and item.get_metadata(0) != null:
		outline_selected.emit(item.get_metadata(0))


func _on_outline_activated() -> void:
	var item := outline.get_selected()
	if item != null and item.get_metadata(0) != null:
		outline_activated.emit(item.get_metadata(0))


# --- Library ---------------------------------------------------------------

func refresh_library(project: Project) -> void:
	var keep := selected_library_id()
	library.clear()
	_lib_ids.clear()
	var defs := project.defs.values()
	defs.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	var counts := project.usage_counts()
	for def in defs:
		var cm: float = project.voxel_size * def.unit * 100.0
		var label := "%s   ·  %s cm blocks" % [def.name, _fmt(cm)]
		var uses: int = counts.get(def.id, 0)
		if def.id == project.root_id:
			label += "  ·  world"
		elif uses == 0:
			label += "  ·  unused"
		elif uses > 1:
			label += "  ·  ×%d" % uses
		library.add_item(label)
		_lib_ids.append(def.id)
		if def.id == keep:
			library.select(library.item_count - 1)


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.01)).trim_suffix(".0")


func selected_library_id() -> String:
	var sel := library.get_selected_items()
	return "" if sel.is_empty() else _lib_ids[sel[0]]


func _on_library_selected(i: int) -> void:
	name_edit.text = library.get_item_text(i).get_slice("   ·", 0)


func _rename_selected() -> void:
	var id := selected_library_id()
	if id != "":
		rename_object.emit(id, name_edit.text)


func _place() -> void:
	var id := selected_library_id()
	if id != "":
		place_object.emit(id)


func _delete() -> void:
	var id := selected_library_id()
	if id != "":
		delete_object.emit(id)


func _export() -> void:
	var id := selected_library_id()
	if id == "":
		return
	_dialog_mode = "export:" + id
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = library.get_item_text(library.get_selected_items()[0]).get_slice("   ·", 0) + ".ourobj.json"
	file_dialog.popup_centered_ratio(0.6)


func _import() -> void:
	_dialog_mode = "import"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if _dialog_mode.begins_with("export:"):
		export_object.emit(_dialog_mode.trim_prefix("export:"), path)
	elif _dialog_mode == "import":
		import_object.emit(path)

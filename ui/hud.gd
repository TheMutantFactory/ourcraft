class_name Hud
extends CanvasLayer
## On-screen interface: crosshair, breadcrumb, hotbar, toasts, help, and the
## side panel (outline, library, settings) shown when the mouse is released.

signal outline_selected(path: PackedStringArray)
signal outline_activated(path: PackedStringArray)
signal command(name: String)
signal place_object(def_id: String)
signal rename_object(def_id: String, new_name: String)
signal delete_object(def_id: String)
signal export_object(def_id: String, file_path: String)
signal import_object(file_path: String)
signal min_block_changed(cm: float)
signal object_unit_changed(unit: int)

const UNITS := [1, 2, 5, 10, 25, 50, 100]

var context_label: Label
var selection_label: Label
var brush_label: Label
var toast_label: Label
var help_label: Label
var status_label: Label
var hotbar: HBoxContainer
var panel: PanelContainer
var outline: Tree
var library: ItemList
var name_edit: LineEdit
var min_block_spin: SpinBox
var unit_option: OptionButton
var file_dialog: FileDialog

var _toast_time := 0.0
var _swatches: Array = []
var _lib_ids: Array = []
var _suppress := false
var _dialog_mode := ""


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
	top.position = Vector2(16, 14)
	root.add_child(top)
	context_label = _shadow_label(20)
	top.add_child(context_label)
	selection_label = _shadow_label(16)
	selection_label.add_theme_color_override("font_color", Color("#ffd75e"))
	top.add_child(selection_label)

	status_label = _shadow_label(13)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(status_label)
	_pin_top_right(status_label, 14, 400)

	help_label = _shadow_label(14)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_label.text = HELP
	root.add_child(help_label)
	_pin_top_right(help_label, 40, 600)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 18
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	toast_label = _shadow_label(18)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(toast_label)
	brush_label = _shadow_label(15)
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


const HELP := """WASD move · Space jump · Shift sprint · F fly (Space/Shift up/down)
Left click break · Right click place · Middle click pick colour
1–0 colour · Scroll brush size · , . shrink/grow yourself
Q select object (again: walk up the tree) · Shift+Q walk down
Enter edit selected · Backspace leave object · I isolate
N new object here · G move · R rotate · Del delete
Ctrl+C copy · Ctrl+V paste instance · Ctrl+D duplicate · U make unique
Ctrl+Z undo · Ctrl+Shift+Z redo · Ctrl+S save · Ctrl+O reload
Tab panel (outline, library, settings) · H hide help"""


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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	col.add_child(_heading("Outline"))
	outline = Tree.new()
	outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outline.size_flags_stretch_ratio = 1.6
	outline.hide_root = false
	outline.item_selected.connect(_on_outline_selected)
	outline.item_activated.connect(_on_outline_activated)
	col.add_child(outline)
	col.add_child(_buttons([["Edit", "edit"], ["Leave", "leave"], ["Isolate", "isolate"]]))
	col.add_child(_buttons([["Move", "grab"], ["Rotate", "rotate"], ["Unique", "unique"], ["Delete", "delete"]]))

	col.add_child(_heading("Library"))
	library = ItemList.new()
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


func set_palette(colors: Array, current: int) -> void:
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
	help_label.visible = help_label.visible and not on


func panel_open() -> bool:
	return panel.visible


func toggle_help() -> void:
	help_label.visible = not help_label.visible


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
	outline.clear()
	var root_item := outline.create_item()
	_fill_outline(project, root_item, project.root(), PackedStringArray(), edit_path, selected, 0)
	_suppress = false


func _fill_outline(project: Project, item: TreeItem, def: ObjectDef, path: PackedStringArray,
		edit_path: PackedStringArray, selected, depth: int) -> void:
	var text := def.name
	var uses := project.usage_count(def.id)
	if uses > 1:
		text += "  ×%d" % uses
	if path == edit_path:
		text = "✎ " + text
		item.set_custom_color(0, Color("#7fd3ff"))
	item.set_text(0, text)
	item.set_metadata(0, path)
	if selected != null and path == selected:
		item.select(0)
	var on_edit_branch := _is_prefix(path, edit_path) or _is_prefix(edit_path, path)
	var on_sel_branch := selected != null and _is_prefix(path, selected)
	item.collapsed = depth > 0 and not on_edit_branch and not on_sel_branch
	if depth >= Project.MAX_DEPTH:
		return
	for inst in def.children:
		var child_def: ObjectDef = project.defs.get(inst.def_id)
		if child_def == null:
			continue
		var p := path.duplicate()
		p.append(inst.id)
		_fill_outline(project, outline.create_item(item), child_def, p, edit_path, selected, depth + 1)


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
	if item != null:
		outline_selected.emit(item.get_metadata(0))


func _on_outline_activated() -> void:
	var item := outline.get_selected()
	if item != null:
		outline_activated.emit(item.get_metadata(0))


# --- Library ---------------------------------------------------------------

func refresh_library(project: Project) -> void:
	var keep := selected_library_id()
	library.clear()
	_lib_ids.clear()
	var defs := project.defs.values()
	defs.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	for def in defs:
		var cm: float = project.voxel_size * def.unit * 100.0
		var label := "%s   ·  %s cm blocks" % [def.name, _fmt(cm)]
		var uses := project.usage_count(def.id)
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

extends OptionMenu

const TOGGLE := preload("res://ui/option_toggle.tscn")
const ROW_FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")

const DRAG_THRESHOLD := 6.0
const ACCENT := Color(0.815686, 0.701961, 0.0235294, 1)
const DANGER := Color(1.0, 0.352941, 0.352941, 1)
const OK_COLOR := Color(0.509804, 0.807843, 0.313726, 1)
const DIM := Color(0.74902, 0.74902, 0.74902, 1)

@onready var list_box: VBoxContainer = %List
@onready var summary_label: Label = %Summary
@onready var status_label: Label = %Status
@onready var import_btn: Button = %ImportBtn
@onready var restart_bar: PanelContainer = %RestartBar
@onready var restart_label: Label = %RestartLabel
@onready var undo_btn: Button = %UndoBtn
@onready var restart_btn: Button = %RestartBtn
@onready var uninstall_btn: Button = %UninstallBtn
@onready var up_btn: Button = %UpBtn
@onready var down_btn: Button = %DownBtn
@onready var drag_layer: Control = %DragLayer
@onready var detail_head: HBoxContainer = %DetailHead
@onready var detail_buttons: HBoxContainer = %DetailButtons
@onready var empty_label: Label = %EmptyLabel
@onready var detail_scroll: ScrollContainer = %DetailScroll
@onready var detail_icon: TextureRect = %Icon
@onready var detail_initial: Label = %Initial
@onready var detail_name: Label = %DetailName
@onready var detail_meta: Label = %DetailMeta
@onready var detail_error: Label = %DetailError
@onready var detail_desc: Label = %DetailDesc
@onready var detail_deps: Label = %DetailDeps
@onready var detail_adds: Label = %DetailAdds
@onready var detail_override_scripts: Label = %DetailOverrideScripts
@onready var detail_overrides: Label = %DetailOverrides
@onready var detail_min_version: Label = %DetailMinVersion
@onready var detail_min_state: Label = %DetailMinState
@onready var detail_dir: Label = %DetailDir

var _file_dialog: FileDialog
var _confirm: ConfirmationDialog
var _restart_confirm: ConfirmationDialog
var _selected_id: String = ""
var _icon_cache: Dictionary = {}
var _last_mods: Array = []
var _pending_ids: Dictionary = {}
var _pending_irreversible: Dictionary = {}
var _baseline_valid: bool = false
var _baseline_enabled: Dictionary = {}
var _baseline_order: Array = []
var _restoring: bool = false
var _row_hover_id: String = ""

var _row_style_normal: StyleBoxFlat
var _row_style_hover: StyleBoxFlat
var _row_style_selected: StyleBoxFlat
var _row_icon_style: StyleBoxFlat

var _press_row: Control = null
var _press_viewport: Vector2 = Vector2.ZERO
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _drag_row: Control = null
var _drag_origin_index: int = 0
var _spacer: Control = null


func _ready() -> void:
	_build_row_styles()
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.zip", tr("mod_zip_filter"))
	_file_dialog.file_selected.connect(_on_zip_selected)
	add_child(_file_dialog)
	import_btn.pressed.connect(_on_import_pressed)
	uninstall_btn.pressed.connect(_on_uninstall_pressed)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = tr("mod_uninstall")
	_confirm.cancel_button_text = tr("mod_cancel")
	add_child(_confirm)
	_confirm.confirmed.connect(_on_uninstall_confirmed)
	_restart_confirm = ConfirmationDialog.new()
	_restart_confirm.ok_button_text = tr("mod_restart_now")
	_restart_confirm.cancel_button_text = tr("mod_cancel")
	_restart_confirm.dialog_text = tr("mod_restart_confirm")
	add_child(_restart_confirm)
	_restart_confirm.confirmed.connect(_on_restart_confirmed)
	up_btn.pressed.connect(func(): _move_selected(-1))
	down_btn.pressed.connect(func(): _move_selected(1))
	undo_btn.pressed.connect(_on_undo)
	restart_btn.pressed.connect(_on_restart_pressed)
	ModManager.mods_changed.connect(_refresh)
	_refresh()


func menu_show() -> void:
	super()
	status_label.text = ""
	_refresh()


func menu_hide() -> void:
	_cancel_drag()
	super()


func _build_row_styles() -> void:
	_row_style_normal = StyleBoxFlat.new()
	_row_style_normal.bg_color = Color(0.164706, 0.164706, 0.164706, 1)
	_row_style_normal.content_margin_left = 3.0
	_row_style_normal.content_margin_right = 3.0
	_row_style_normal.content_margin_top = 1.0
	_row_style_normal.content_margin_bottom = 1.0
	_row_style_hover = StyleBoxFlat.new()
	_row_style_hover.bg_color = Color(0.196078, 0.196078, 0.196078, 1)
	_row_style_hover.content_margin_left = 3.0
	_row_style_hover.content_margin_right = 3.0
	_row_style_hover.content_margin_top = 1.0
	_row_style_hover.content_margin_bottom = 1.0
	_row_style_hover.border_width_left = 1
	_row_style_hover.border_width_top = 1
	_row_style_hover.border_width_right = 1
	_row_style_hover.border_width_bottom = 1
	_row_style_hover.border_color = Color(0.372549, 0.372549, 0.372549, 1)
	_row_style_selected = StyleBoxFlat.new()
	_row_style_selected.bg_color = Color(0.211765, 0.211765, 0.211765, 1)
	_row_style_selected.content_margin_left = 3.0
	_row_style_selected.content_margin_right = 3.0
	_row_style_selected.content_margin_top = 1.0
	_row_style_selected.content_margin_bottom = 1.0
	_row_style_selected.border_width_left = 1
	_row_style_selected.border_width_top = 1
	_row_style_selected.border_width_right = 1
	_row_style_selected.border_width_bottom = 1
	_row_style_selected.border_color = ACCENT
	_row_icon_style = StyleBoxFlat.new()
	_row_icon_style.bg_color = Color(0.121569, 0.121569, 0.121569, 1)
	_row_icon_style.border_width_left = 1
	_row_icon_style.border_width_top = 1
	_row_icon_style.border_width_right = 1
	_row_icon_style.border_width_bottom = 1
	_row_icon_style.border_color = Color(0.294118, 0.294118, 0.294118, 1)


func _refresh() -> void:
	if list_box == null or _restoring:
		return
	_row_hover_id = ""
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	_last_mods = ModManager.list_mods()
	var groups := {
		"attention": [],
		"enabled": [],
		"disabled": [],
	}
	var known: Dictionary = {}
	for m in _last_mods:
		var id := str(m.id)
		known[id] = true
		groups[_group_key(m)].append(m)
	if not known.has(_selected_id):
		_selected_id = str(_last_mods[0].id) if not _last_mods.is_empty() else ""
	for key in ["attention", "enabled", "disabled"]:
		var items: Array = groups[key]
		if items.is_empty():
			continue
		list_box.add_child(_make_group_header(key, items.size()))
		for m in items:
			list_box.add_child(_make_row(m))
	_update_summary()
	_update_restart_bar()
	_update_arrows()
	_update_detail()


func _group_key(m: Dictionary) -> String:
	if str(m.get("error", "")) != "":
		return "attention"
	var required := str(m.get("game_version", ""))
	if required != "" and not bool(m.get("game_version_ok", true)):
		return "attention"
	return "enabled" if bool(m.get("enabled", false)) else "disabled"


func _make_group_header(key: String, count: int) -> Label:
	var label := Label.new()
	label.set_meta("group_header", true)
	label.custom_minimum_size = Vector2(0, 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ROW_FONT)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", DANGER if key == "attention" else DIM)
	var text_key := "mod_group_attention"
	if key == "enabled":
		text_key = "mod_group_enabled"
	elif key == "disabled":
		text_key = "mod_group_disabled"
	label.text = tr(text_key) % count
	return label


func _make_row(m: Dictionary) -> PanelContainer:
	var id := str(m.id)
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("mod_id", id)
	row.set_meta("mod_data", m)
	row.set_meta("is_row", true)
	row.add_theme_stylebox_override("panel", _row_style_for(id))

	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	var icon_slot := PanelContainer.new()
	icon_slot.custom_minimum_size = Vector2(20, 20)
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.add_theme_stylebox_override("panel", _row_icon_style)
	box.add_child(icon_slot)

	var icon := TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := _load_icon(str(m.get("icon", "")))
	icon.texture = tex
	icon.visible = tex != null
	icon_slot.add_child(icon)

	var initial := Label.new()
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_override("font", ROW_FONT)
	initial.add_theme_font_size_override("font_size", 10)
	initial.add_theme_color_override("font_color", ACCENT)
	initial.text = _name_initial(str(m.get("name", id)), id)
	initial.visible = tex == null
	icon_slot.add_child(initial)

	var label := Label.new()
	label.name = "Name"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(m.get("name", id))
	_apply_row_font(label)
	box.add_child(label)

	var pending := Label.new()
	pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pending.add_theme_font_override("font", ROW_FONT)
	pending.add_theme_font_size_override("font_size", 8)
	pending.add_theme_color_override("font_color", ACCENT)
	pending.text = tr("mod_detail_pending")
	pending.visible = _is_pending(id)
	box.add_child(pending)

	var toggle = TOGGLE.instantiate()
	toggle.name = "Toggle"
	toggle.set("on", bool(m.get("enabled", false)))
	toggle.connect("toggled", func(on: bool): _on_toggle(id, on))
	box.add_child(toggle)

	row.mouse_entered.connect(func(): _on_row_hover(row, true))
	row.mouse_exited.connect(func(): _on_row_hover(row, false))
	row.gui_input.connect(func(event: InputEvent): _on_row_gui_input(row, event))
	return row


func _apply_row_font(label: Label) -> void:
	label.add_theme_font_override("font", ROW_FONT)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("shadow_outline_size", 2)


func _load_icon(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = load(path)
	else:
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	_icon_cache[path] = tex
	return tex


func _row_style_for(id: String) -> StyleBoxFlat:
	if id == _selected_id:
		return _row_style_selected
	if id == _row_hover_id:
		return _row_style_hover
	return _row_style_normal


func _apply_row_style(row: Control) -> void:
	row.add_theme_stylebox_override("panel", _row_style_for(str(row.get_meta("mod_id", ""))))


func _on_row_hover(row: Control, entered: bool) -> void:
	if _drag_active:
		return
	_row_hover_id = str(row.get_meta("mod_id", "")) if entered else ""
	for c in _row_children():
		_apply_row_style(c)


func _row_children() -> Array:
	var out: Array = []
	for c in list_box.get_children():
		if c.has_meta("is_row"):
			out.append(c)
	return out


func _select(row: Control) -> void:
	var id := str(row.get_meta("mod_id", ""))
	if id == _selected_id:
		return
	_selected_id = id
	for c in _row_children():
		_apply_row_style(c)
	_update_arrows()
	_update_detail()


func _update_arrows() -> void:
	var ids := _current_ids()
	var pos := ids.find(_selected_id)
	up_btn.disabled = pos <= 0
	down_btn.disabled = pos < 0 or pos >= ids.size() - 1
	uninstall_btn.disabled = _selected_id == ""


func _current_ids() -> Array:
	var ids: Array = []
	for c in _row_children():
		ids.append(str(c.get_meta("mod_id", "")))
	return ids


func _move_selected(delta: int) -> void:
	var ids := _current_ids()
	var pos := ids.find(_selected_id)
	var target := pos + delta
	if pos < 0 or target < 0 or target >= ids.size():
		return
	_ensure_baseline()
	var first := str(ids[pos])
	var second := str(ids[target])
	ids[pos] = second
	ids[target] = first
	_pending_ids[first] = true
	_pending_ids[second] = true
	ModManager.set_order(ids)
	_update_restart_bar()


func _on_row_gui_input(row: Control, event: InputEvent) -> void:
	if _drag_active:
		return
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	if not pressed:
		return
	row.accept_event()
	_press_row = row
	_press_viewport = row.get_global_transform() * event.position
	_drag_grab_offset = _press_viewport - row.global_position


func _input(event: InputEvent) -> void:
	if _press_row == null or not is_instance_valid(_press_row):
		return
	if _drag_active:
		var p := _event_viewport_pos(event)
		if p != Vector2.INF:
			_drag_row.global_position = p - _drag_grab_offset
			_move_spacer_to(_target_row_index(p.y))
		if _is_release(event):
			_end_drag()
			_press_row = null
		get_viewport().set_input_as_handled()
		return
	var p2 := _event_viewport_pos(event)
	if p2 != Vector2.INF and p2.distance_to(_press_viewport) > DRAG_THRESHOLD:
		_start_drag()
		get_viewport().set_input_as_handled()
		return
	if _is_release(event):
		var released: Control = _press_row
		_select(released)
		_press_row = null


func _event_viewport_pos(event: InputEvent) -> Vector2:
	if event is InputEventScreenDrag:
		return event.position
	if event is InputEventScreenTouch:
		return event.position
	if event is InputEventMouseMotion:
		return event.position
	return Vector2.INF


func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and not event.pressed:
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		return true
	return false


func _start_drag() -> void:
	_drag_active = true
	_drag_row = _press_row
	_drag_origin_index = _drag_row.get_index()
	var h := _drag_row.size.y
	_spacer = Control.new()
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.custom_minimum_size = Vector2(0, h)
	_spacer.size = Vector2(0, h)
	var idx := _drag_row.get_index()
	list_box.add_child(_spacer)
	list_box.move_child(_spacer, idx)
	list_box.remove_child(_drag_row)
	drag_layer.add_child(_drag_row)
	_drag_row.size = Vector2(list_box.size.x, h)
	_drag_row.global_position = _press_viewport - _drag_grab_offset


func _move_spacer_to(target: int) -> void:
	if _spacer == null or not is_instance_valid(_spacer):
		return
	var rows := _row_children()
	target = clampi(target, 0, rows.size())
	var child_idx := list_box.get_child_count()
	if target < rows.size():
		child_idx = rows[target].get_index()
	if _spacer.get_index() < child_idx:
		child_idx -= 1
	child_idx = clampi(child_idx, 0, list_box.get_child_count() - 1)
	if _spacer.get_index() != child_idx:
		list_box.move_child(_spacer, child_idx)


func _target_row_index(y: float) -> int:
	var idx := 0
	for row in _row_children():
		if y > row.global_position.y + row.size.y * 0.5:
			idx += 1
		else:
			break
	return idx


func _end_drag() -> void:
	_drag_active = false
	var idx := _spacer.get_index()
	var id := str(_drag_row.get_meta("mod_id", ""))
	var p := _drag_row.get_parent()
	if p != null:
		p.remove_child(_drag_row)
	list_box.add_child(_drag_row)
	list_box.move_child(_drag_row, idx)
	list_box.remove_child(_spacer)
	_spacer.queue_free()
	_spacer = null
	_drag_row = null
	_selected_id = id
	_pending_ids[id] = true
	var ids := _current_ids()
	ModManager.set_order(ids)


func _cancel_drag() -> void:
	_press_row = null
	if not _drag_active:
		return
	_drag_active = false
	if _spacer != null and is_instance_valid(_spacer):
		var p := _drag_row.get_parent()
		if p != null:
			p.remove_child(_drag_row)
		list_box.remove_child(_spacer)
		_spacer.queue_free()
		_spacer = null
		var idx := clampi(_drag_origin_index, 0, list_box.get_child_count())
		list_box.add_child(_drag_row)
		list_box.move_child(_drag_row, idx)
	_drag_row = null


func _update_summary() -> void:
	var effective := 0
	for m in _last_mods:
		if bool(m.get("enabled", false)) and bool(m.get("mounted", false)) and str(m.get("error", "")) == "":
			effective += 1
	summary_label.text = tr("mod_summary") % [_last_mods.size(), effective, _pending_count()]


func _update_restart_bar() -> void:
	var count := _pending_count()
	restart_bar.visible = count > 0
	restart_label.text = tr("mod_restart_bar") % count
	undo_btn.disabled = _pending_ids.is_empty()


func _pending_count() -> int:
	var all: Dictionary = {}
	for id in _pending_ids:
		all[str(id)] = true
	for id in _pending_irreversible:
		all[str(id)] = true
	return all.size()


func _is_pending(id: String) -> bool:
	return _pending_ids.has(id) or _pending_irreversible.has(id)


func _ensure_baseline() -> void:
	if _baseline_valid:
		return
	_baseline_valid = true
	_baseline_enabled.clear()
	for m in ModManager.list_mods():
		_baseline_enabled[str(m.id)] = bool(m.enabled)
	_baseline_order = ModManager.get_order()


func _on_toggle(id: String, on: bool) -> void:
	_ensure_baseline()
	_pending_ids[id] = true
	ModManager.set_enabled(id, on)


func _on_undo() -> void:
	if not _baseline_valid or _pending_ids.is_empty():
		return
	_restoring = true
	for id in _baseline_enabled:
		ModManager.set_enabled(str(id), bool(_baseline_enabled[id]))
	ModManager.set_order(_baseline_order)
	_pending_ids.clear()
	_baseline_valid = false
	_restoring = false
	status_label.text = ""
	_refresh()


func _on_restart_pressed() -> void:
	_restart_confirm.popup_centered()


func _on_restart_confirmed() -> void:
	get_tree().quit()


func _on_import_pressed() -> void:
	_file_dialog.popup_centered_ratio()


func _on_zip_selected(path: String) -> void:
	var r := ModManager.import_zip(path)
	if r.get("ok", false):
		var id := str(r.get("id", ""))
		if id != "":
			_pending_irreversible[id] = true
		status_label.text = tr("mod_import_ok") % id
	else:
		status_label.text = tr("mod_import_fail") % str(r.get("error", ""))
	_refresh()


func _on_uninstall_pressed() -> void:
	if _selected_id == "":
		status_label.text = tr("mod_uninstall_select")
		return
	var name := _mod_display_name(_selected_id)
	_confirm.dialog_text = tr("mod_uninstall_confirm") % name
	_confirm.popup_centered()


func _on_uninstall_confirmed() -> void:
	var id := _selected_id
	if id == "":
		return
	var name := _mod_display_name(id)
	_selected_id = ""
	var r := ModManager.uninstall(id)
	if not r.get("ok", false):
		_refresh()
		status_label.text = tr("mod_uninstall_fail") % str(r.get("error", ""))
		return
	_pending_ids.erase(id)
	if bool(r.get("restart_required", false)) or not bool(r.get("deleted", false)):
		_pending_irreversible[id] = true
	else:
		_pending_irreversible.erase(id)
	if bool(r.get("deleted", false)):
		status_label.text = tr("mod_uninstall_ok") % name
	else:
		status_label.text = tr("mod_uninstall_pending")
	if bool(r.get("restart_required", false)):
		status_label.text += "  " + tr("mod_restart_notice")
	_refresh()


func _mod_display_name(id: String) -> String:
	for m in ModManager.list_mods():
		if str(m.id) == id:
			return str(m.name)
	return id


func _find_mod(id: String) -> Dictionary:
	for m in _last_mods:
		if str(m.id) == id:
			return m
	return {}


func _update_detail() -> void:
	var m := _find_mod(_selected_id)
	var has_mod := not m.is_empty()
	empty_label.visible = not has_mod
	detail_head.visible = has_mod
	detail_scroll.visible = has_mod
	detail_buttons.visible = has_mod
	detail_error.visible = false
	if not has_mod:
		return
	var name := str(m.get("name", _selected_id))
	detail_name.text = name
	var meta: Array = []
	var version := str(m.get("version", ""))
	var author := str(m.get("author", ""))
	if version != "":
		meta.append("v" + version)
	if author != "":
		meta.append(author)
	if _is_pending(_selected_id):
		meta.append(tr("mod_detail_pending"))
	detail_meta.text = _join_values(meta, "  ")
	detail_meta.visible = not meta.is_empty()

	var tex := _load_icon(str(m.get("icon", "")))
	detail_icon.texture = tex
	detail_icon.visible = tex != null
	detail_initial.visible = tex == null
	detail_initial.text = _name_initial(name, _selected_id)

	var err := str(m.get("error", ""))
	detail_error.text = tr("mod_tag_error") % err
	detail_error.visible = err != ""

	var desc := str(m.get("description", ""))
	detail_desc.text = desc
	detail_desc.visible = desc != ""

	detail_deps.text = tr("mod_detail_dependencies") % _join_or_none(Array(m.get("dependencies", [])))
	detail_adds.text = tr("mod_detail_adds") % _content_summary(m.get("adds", {}))

	var scripts: Array = []
	for p in Array(m.get("replace_paths", [])):
		scripts.append(str(p).get_file())
	detail_override_scripts.text = tr("mod_detail_override_scripts") % _join_or_none(scripts)
	detail_override_scripts.visible = not scripts.is_empty()

	var overrides := Array(m.get("overrides", []))
	detail_overrides.text = tr("mod_detail_overrides") % _join_or_none(overrides)
	detail_overrides.visible = not overrides.is_empty()

	var required := str(m.get("game_version", ""))
	detail_min_version.text = tr("mod_detail_min_game_version") % (required if required != "" else tr("mod_detail_undeclared"))
	var current := str(Game.version_number) if is_instance_valid(Game) else ""
	if required == "" or current == "":
		detail_min_state.visible = false
	elif bool(m.get("game_version_ok", true)):
		detail_min_state.text = tr("mod_detail_min_met") % current
		detail_min_state.add_theme_color_override("font_color", OK_COLOR)
		detail_min_state.visible = true
	else:
		detail_min_state.text = tr("mod_detail_min_unmet") % current
		detail_min_state.add_theme_color_override("font_color", DANGER)
		detail_min_state.visible = true

	detail_dir.text = tr("mod_detail_dir") % str(m.get("dir", ""))


func _name_initial(name: String, id: String) -> String:
	var text := name.strip_edges()
	if text == "":
		text = id.strip_edges()
	if text == "":
		return "?"
	var skip := [" ", "　", "\t", "\n", "·", "-", "_", ".", ":", "[", "]", "(", ")", "（", "）", "【", "】", "/", "\\"]
	for i in text.length():
		var ch := text.substr(i, 1)
		if skip.has(ch):
			continue
		return ch.to_upper()
	return "?"


func _join_or_none(values: Array) -> String:
	if values.is_empty():
		return tr("mod_detail_none")
	return _join_values(values, " · ")


func _join_values(values: Array, separator: String) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append(str(v))
	return separator.join(parts)


func _content_summary(adds) -> String:
	if not (adds is Dictionary) or adds.is_empty():
		return tr("mod_detail_none")
	var parts: Array = []
	for kind in ["characters", "societies", "upgrades", "enemies", "supports", "clothes", "shop_characters", "game_modes", "levels"]:
		if adds.has(kind):
			parts.append("%s %d" % [tr("mod_kind_" + str(kind)), int(adds[kind])])
	return _join_values(parts, " · ") if not parts.is_empty() else tr("mod_detail_none")

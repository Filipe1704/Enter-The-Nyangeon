extends CanvasLayer

signal level_is_selected
signal player_selected

@onready var animation_player = $AnimationPlayer
@onready var level_box: VBoxContainer = $Node2D2/Node2D/Node2D/VBoxContainer
@onready var support_select = $Node2D2/support_ui
@onready var mode_box: GridContainer = $Node2D2/gamemode_button/MarginContainer/ScrollContainer/GridContainer
@onready var return_button: Button = $Node2D2/return

const LEVEL_BUTTON := preload("res://ui/level_button.tscn")

var player: String
var transition_started: bool = false
var _keyboard_ready := false
var _selection_pending := false
var _last_focus: Dictionary = {}

func _ready():
	GameEvents.player_card_id.connect(get_player_id)
	GameEvents.level_select_in.connect(level_menu_in)
	_inject_mod_levels()
	level_is_selected.connect(_lock_selection)
	support_select.cards_changed.connect(_bind_focus_controls)
	_set_auxiliary_enabled(false)
	_bind_focus_controls()

func _set_auxiliary_enabled(enabled: bool) -> void:
	support_select.set_interactive(enabled)
	for mode in mode_box.get_children():
		mode.set_interactive(enabled)
	return_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	return_button.disabled = not enabled

func _lock_selection() -> void:
	_selection_pending = true
	_set_auxiliary_enabled(false)

func _groups() -> Array:
	return [[support_select.main_card], level_box.get_children(), mode_box.get_children(), [return_button]]

func _focus_group(control: Control) -> int:
	if control == null:
		return 1
	if support_select.is_ancestor_of(control):
		return 0
	if mode_box.is_ancestor_of(control):
		return 2
	if control == return_button:
		return 3
	return 1

func _create_focus_outline(control: Control) -> Control:
	if control == support_select.main_card:
		# 主卡会裁剪圆角，列表又是它的兄弟节点；焦点框必须独立绘制在二者上方。
		var outline := Panel.new()
		var style := StyleBoxFlat.new()
		style.draw_center = false
		style.border_color = Color.WHITE
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.anti_aliasing = false
		outline.add_theme_stylebox_override("panel", style)
		outline.z_index = 1
		support_select.add_child(outline)
		var sync_rect := func():
			outline.position = control.position
			outline.size = control.size
		control.item_rect_changed.connect(sync_rect)
		sync_rect.call()
		return outline
	var outline := ReferenceRect.new()
	outline.editor_only = false
	outline.border_color = Color.WHITE
	outline.border_width = 2
	control.add_child(outline)
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return outline

func _bind_focus_controls() -> void:
	var controls: Array = [support_select.main_card]
	controls.append_array(support_select.support_box.get_children())
	controls.append_array(level_box.get_children())
	controls.append_array(mode_box.get_children())
	for control: Control in controls:
		if control.is_queued_for_deletion() or control.has_meta("level_focus_outline"):
			continue
		control.set_meta("level_focus_outline", true)
		# 焦点边框与已选择状态分开，避免模式填色或卡片动画抹掉焦点提示。
		var outline := _create_focus_outline(control)
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.visible = false
		control.focus_entered.connect(func():
			outline.show()
			_last_focus[_focus_group(control)] = control
		)
		control.focus_exited.connect(outline.hide)

func _move_focus(control: Control) -> void:
	control.grab_focus()
	var ancestor := control.get_parent()
	while ancestor != null and ancestor != self:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible.call_deferred(control)
		ancestor = ancestor.get_parent()

func _input(event: InputEvent) -> void:
	if not visible or not _keyboard_ready:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not event.is_echo():
			_handle_back()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if _selection_pending:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_focus_next", true) or event.is_action_pressed("ui_focus_prev", true) or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_next", true) or event.is_action_pressed("ui_focus_prev", true):
		get_viewport().set_input_as_handled()
		if event.is_echo():
			return
		var group := _focus_group(focused)
		if group == 0:
			support_select.close_list(false)
			_last_focus[0] = support_select.main_card
		var direction := -1 if event.is_action_pressed("ui_focus_prev", true) else 1
		var next := posmod(group + direction, 4)
		var controls: Array = _groups()[next]
		if not controls.is_empty():
			var target: Control = _last_focus.get(next, controls[0])
			if not is_instance_valid(target) or not target.is_visible_in_tree() or target.focus_mode == Control.FOCUS_NONE:
				target = controls[0]
			_move_focus(target)
		return
	if focused == return_button and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if not event.is_echo():
			_handle_back()
		return
	var step := 0
	var horizontal := event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true)
	if event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_left", true):
		step = -1
	elif event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_right", true):
		step = 1
	if step == 0:
		return
	get_viewport().set_input_as_handled()
	var group := _focus_group(focused)
	var controls: Array = _groups()[group]
	if group == 0:
		controls = support_select.support_box.get_children() if support_select.list_open else []
	if (group != 2 and horizontal) or controls.is_empty():
		return
	if group == 2 and not horizontal:
		step *= mode_box.columns
	var index := controls.find(focused)
	_move_focus(controls[clampi(index + step, 0, controls.size() - 1)])

func _handle_back() -> void:
	if transition_started:
		return
	if support_select.list_open and support_select.has_keyboard_focus():
		support_select.close_list()
		return
	_keyboard_ready = false
	_set_auxiliary_enabled(false)
	for button in level_box.get_children():
		button.cancel_selection()
	SoundManager.play_sfx("UISounds2")
	GameEvents.emit_level_select_out()
	animation_player.play("RESET")

func _inject_mod_levels() -> void:
	for lv in ModManager.get_content("levels"):
		if lv == null:
			continue
		var ins = LEVEL_BUTTON.instantiate()
		ins.level = lv
		ins.level_select = self
		level_box.add_child(ins)

func _unhandled_input(event):
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_handle_back()

func get_player_id(player_id: String):
	player = player_id

func emit_player_selected():
	player_selected.emit()

func level_menu_in():
	_keyboard_ready = false
	_selection_pending = false
	_last_focus.clear()
	_set_auxiliary_enabled(false)
	transition_started = false
	SoundManager.play_sfx("UISounds1")
	animation_player.play("select_in")
	await animation_player.animation_finished
	await get_tree().process_frame
	if visible and not transition_started and level_box.get_child_count() > 0:
		_keyboard_ready = true
		_set_auxiliary_enabled(true)
		var first_button: Control = level_box.get_child(0)
		if first_button.focus_mode != Control.FOCUS_NONE:
			first_button.grab_focus()

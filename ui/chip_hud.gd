extends CanvasLayer

@export var debug_show_counts: bool = false

@onready var slot_box: HBoxContainer = $Root/Slots

var _manager: Node
var _slots: Array[Dictionary] = []
var _bind_retries := 0
var _ui_shown: bool = true

func _ready() -> void:
	visible = false
	GameEvents.ui_visible.connect(_on_ui_visible)
	GameEvents.game_over.connect(_on_game_over)
	_bind_manager()

func _bind_manager() -> void:
	_manager = get_tree().get_first_node_in_group("ChipManager")
	if _manager == null:
		_bind_retries += 1
		if _bind_retries <= 60:
			call_deferred("_bind_manager")
		return
	if _manager.has_signal("chips_changed"):
		_manager.chips_changed.connect(_on_chips_changed)
	if _manager.has_signal("chip_assigned"):
		_manager.chip_assigned.connect(_on_chip_count_changed)
	if _manager.has_signal("chip_released"):
		_manager.chip_released.connect(_on_chip_count_changed)
	_build_slots()
	_append_manager_state()

func _build_slots() -> void:
	if not _slots.is_empty():
		return
	var slot_count: int = 3
	if _manager != null and _manager.get("active_chip_limit") != null:
		slot_count = clampi(int(_manager.active_chip_limit), 1, 6)
	slot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in slot_count:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = Vector2(24, 24)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
		style.border_color = Color(1.0, 1.0, 1.0, 0.18)
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		style.content_margin_left = 2.0
		style.content_margin_right = 2.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0
		panel.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 2)
		panel.add_child(row)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var count_label := Label.new()
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.add_theme_font_size_override("font_size", 8)
		count_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
		count_label.visible = debug_show_counts
		row.add_child(count_label)
		slot_box.add_child(panel)
		_slots.append({
			"panel": panel,
			"icon": icon,
			"count": count_label,
		})
	_clear_slots()

func _clear_slots() -> void:
	for slot in _slots:
		(slot["panel"] as Control).visible = false
	visible = false

func _on_chips_changed(active_chips: Array, counts: Array, _cap: int) -> void:
	_clear_slots()
	if active_chips.is_empty():
		return
	for i in _slots.size():
		if i >= active_chips.size():
			break
		var chip: GameMode = active_chips[i]
		var slot: Dictionary = _slots[i]
		(slot["panel"] as Control).visible = true
		(slot["icon"] as TextureRect).texture = chip.game_mode_icon
		var count := int(counts[i]) if i < counts.size() else 0
		(slot["count"] as Label).text = "F" if chip.is_field_chip() else str(count)
	visible = _ui_shown

func _on_chip_count_changed(_index: int, _count: int) -> void:
	if _manager == null:
		return
	_append_manager_state()

func _append_manager_state() -> void:
	if _manager == null or not _manager.has_method("get_active_chips"):
		return
	_on_chips_changed(
		_manager.get_active_chips(),
		_manager.get_chip_counts(),
		int(_manager.get_round_cap())
	)

func _on_ui_visible(now_visible: bool) -> void:
	_ui_shown = now_visible
	visible = now_visible and _has_active_chips()

func _on_game_over(_player_dead: bool) -> void:
	visible = false

func _has_active_chips() -> bool:
	if _manager == null or not _manager.has_method("get_active_chips"):
		return false
	return not _manager.get_active_chips().is_empty()

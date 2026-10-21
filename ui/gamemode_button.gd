extends Node2D

signal enemy_mod_visibility_changed(visible: bool)

const HAVOC_ID := "havoc"

@export var gamemode_card: Array[GameMode]

@onready var gamemode_type: PackedScene = preload("res://ui/gamemode_type.tscn")
@onready var game_mod_box: GridContainer = %game_mod_box
@onready var enemy_mod_box: GridContainer = %enemy_mod_box
@onready var enemy_mod_section: VBoxContainer = $MarginContainer/ScrollContainer/VBoxContainer/VBoxContainer
@onready var enemy_mod_scroll: ScrollContainer = $MarginContainer/ScrollContainer/VBoxContainer/ScrollContainer2
@onready var enemy_mod_title: Label = $MarginContainer/ScrollContainer/VBoxContainer/VBoxContainer/Label

var _game_modes: Array[GameMode] = []
var _enemy_mods: Array[GameMode] = []
var _cards_by_id: Dictionary = {}
var _havoc_auto_selected := false
var _auto_toggle := false
var _required_enemy_mods := 0
var _title_base_color: Color
var _warning_tween: Tween

func _ready() -> void:
	_title_base_color = enemy_mod_title.get_theme_color("font_color")
	_collect_modes()
	add_gamemode_card()
	_refresh_enemy_mod_title()
	_update_enemy_mod_visibility()

func _collect_modes() -> void:
	var seen: Dictionary = {}
	for mode in gamemode_card:
		_append_mode(mode, seen)
	for mode in ModManager.get_base_game_modes():
		if mode != null and mode.chip_enabled:
			_append_mode(mode, seen)
	for mode in ModManager.get_content("game_modes"):
		_append_mode(mode, seen)

func _append_mode(mode: GameMode, seen: Dictionary) -> void:
	if mode == null or seen.has(mode.game_mode_id):
		return
	seen[mode.game_mode_id] = true
	if mode.chip_enabled:
		_enemy_mods.append(mode)
	else:
		_game_modes.append(mode)

func add_gamemode_card() -> void:
	for mode in _game_modes:
		_add_card(mode, game_mod_box)
	for mode in _enemy_mods:
		_add_card(mode, enemy_mod_box)

func _add_card(mode: GameMode, target: GridContainer) -> void:
	var mode_card = gamemode_type.instantiate()
	mode_card.gamemode_card = mode
	target.add_child(mode_card)
	mode_card.get_gamemode_card()
	mode_card.selection_changed.connect(_on_mode_selection_changed)
	_cards_by_id[mode.game_mode_id] = mode_card

func _on_mode_selection_changed(id: String, _selected: bool) -> void:
	if id == HAVOC_ID:
		if not _auto_toggle:
			_havoc_auto_selected = false
		_update_enemy_mod_visibility()
	else:
		_refresh_enemy_mod_title()

func is_enemy_mod_visible() -> bool:
	return enemy_mod_section.visible

func get_selected_mod_count() -> int:
	var count := 0
	for mode in _enemy_mods:
		var card = _cards_by_id.get(mode.game_mode_id)
		if card != null and card.on_selected:
			count += 1
	return count

func get_selected_enemy_mod_count() -> int:
	return get_selected_mod_count()

func get_selected_field_mod_count() -> int:
	var count := 0
	for mode in _enemy_mods:
		if mode == null or not mode.is_field_chip():
			continue
		var card = _cards_by_id.get(mode.game_mode_id)
		if card != null and card.on_selected:
			count += 1
	return count

func ensure_mode_selected(id: String, selected: bool, auto_selected: bool = false) -> bool:
	var card = _cards_by_id.get(id)
	if card == null:
		return false
	if card.on_selected == selected:
		if id == HAVOC_ID and selected and not auto_selected:
			_havoc_auto_selected = false
		return true
	_auto_toggle = true
	if selected:
		card.add_game_mode()
	else:
		card.erase_game_mode()
	_auto_toggle = false
	if id == HAVOC_ID:
		_havoc_auto_selected = auto_selected if selected else false
	return true

func is_havoc_auto_selected() -> bool:
	return _havoc_auto_selected

func release_auto_havoc() -> bool:
	if not _havoc_auto_selected:
		return false
	if PlayerData.game_mode.has(HAVOC_ID):
		ensure_mode_selected(HAVOC_ID, false, true)
	_havoc_auto_selected = false
	return true

func confirm_havoc_auto_selection() -> void:
	_havoc_auto_selected = false

func set_enemy_mod_requirement(min_mods: int) -> void:
	_required_enemy_mods = maxi(0, min_mods)
	_refresh_enemy_mod_title()

func clear_enemy_mod_requirement() -> void:
	_required_enemy_mods = 0
	_refresh_enemy_mod_title()

func _update_enemy_mod_visibility() -> void:
	var visible_now := PlayerData.game_mode.has(HAVOC_ID)
	var changed := enemy_mod_section.visible != visible_now or enemy_mod_scroll.visible != visible_now
	enemy_mod_section.visible = visible_now
	enemy_mod_scroll.visible = visible_now
	if visible_now:
		_refresh_enemy_mod_title()
	else:
		_required_enemy_mods = 0
		_stop_enemy_mod_warning()
	if changed:
		enemy_mod_visibility_changed.emit(visible_now)

func _refresh_enemy_mod_title() -> void:
	var count := get_selected_enemy_mod_count()
	if _required_enemy_mods > 0:
		enemy_mod_title.text = "ENEMY MOD (%d/%d)" % [count, _required_enemy_mods]
	else:
		enemy_mod_title.text = "ENEMY MOD (%d)" % count

func play_enemy_mod_warning() -> void:
	if not enemy_mod_section.visible:
		return
	_stop_enemy_mod_warning()
	var red := Color(1.0, 0.2, 0.2, _title_base_color.a)
	_warning_tween = create_tween()
	for _i in 2:
		_warning_tween.tween_method(_set_enemy_mod_title_color, _title_base_color, red, 0.08)
		_warning_tween.tween_method(_set_enemy_mod_title_color, red, _title_base_color, 0.12)
	_warning_tween.finished.connect(func():
		_set_enemy_mod_title_color(_title_base_color)
		_warning_tween = null
	)

func _stop_enemy_mod_warning() -> void:
	if _warning_tween != null and _warning_tween.is_valid():
		_warning_tween.kill()
	_warning_tween = null
	_set_enemy_mod_title_color(_title_base_color)

func _set_enemy_mod_title_color(color: Color) -> void:
	enemy_mod_title.add_theme_color_override("font_color", color)

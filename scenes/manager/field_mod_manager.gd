class_name FieldModManager
extends Node

signal field_mod_started(chip: GameMode, effect: Node)
signal field_mod_stopped(chip: GameMode, effect: Node)

const ROOT_GROUP := "FieldModRoot"

var _manager: Node
var _bind_retries := 0
var _entries: Array[Dictionary] = []
var _pending_chips: Array = []
var _apply_queued := false

func _ready() -> void:
	add_to_group("FieldModManager")
	GameEvents.round_end.connect(clear_all)
	GameEvents.round_upgrade.connect(clear_all)
	GameEvents.game_over.connect(_on_game_over)
	GameEvents.test_room_reset.connect(clear_all)
	_bind_manager()

func _bind_manager() -> void:
	_manager = get_tree().get_first_node_in_group("ChipManager")
	if _manager == null:
		_bind_retries += 1
		if _bind_retries <= 60:
			call_deferred("_bind_manager")
		return
	if _manager.has_signal("field_chips_changed"):
		if not _manager.field_chips_changed.is_connected(apply_field_chips):
			_manager.field_chips_changed.connect(apply_field_chips)

func apply_field_chips(chips: Array) -> void:
	_pending_chips = chips.duplicate()
	if _apply_queued:
		return
	_apply_queued = true
	call_deferred("_apply_pending")

func _apply_pending() -> void:
	_apply_queued = false
	var chips := _pending_chips.duplicate()
	_pending_chips.clear()
	clear_all()
	for chip in chips:
		if chip is GameMode:
			_start_chip(chip)

func clear_all() -> void:
	_pending_chips.clear()
	var effects: Array[Node] = []
	for entry in _entries:
		var effect = entry.get("effect")
		if effect is Node:
			effects.append(effect)
	for effect in effects:
		_remove_entry(effect, true)

func get_active_effects() -> Array:
	var out: Array = []
	for entry in _entries:
		out.append(entry.get("effect"))
	return out

func _start_chip(chip: GameMode) -> void:
	if chip == null or not chip.is_field_chip():
		return
	if chip.chip_field_scene == null:
		push_warning("FieldModManager: '%s' has no chip_field_scene" % chip.game_mode_id)
		return
	if ExtensionHooks.intercept_named("field_mod_spawn_gate", [chip]):
		return
	var effect := chip.chip_field_scene.instantiate()
	if effect == null:
		return
	if not effect.has_method("start"):
		push_warning("FieldModManager: '%s' effect has no start()" % chip.game_mode_id)
		effect.queue_free()
		return
	var root := _effect_root()
	if root == null:
		effect.queue_free()
		return
	effect.name = "FieldMod_%s" % chip.game_mode_id
	root.add_child(effect)
	_entries.append({"chip": chip, "effect": effect})
	var exit_cb := Callable(self, "_on_effect_exiting").bind(effect)
	if not effect.tree_exiting.is_connected(exit_cb):
		effect.tree_exiting.connect(exit_cb)
	if effect.has_signal("finished"):
		effect.finished.connect(_on_effect_finished.bind(effect), CONNECT_ONE_SHOT)
	effect.call("start", chip)
	if not is_instance_valid(effect) or effect.is_queued_for_deletion():
		_remove_entry(effect, false)
		return
	field_mod_started.emit(chip, effect)
	ExtensionHooks.notify_named("on_field_mod_started", [chip, effect])

func _effect_root() -> Node:
	var root := get_tree().get_first_node_in_group(ROOT_GROUP)
	if root != null and is_instance_valid(root):
		return root
	return get_tree().current_scene

func _remove_entry(effect: Node, free_effect: bool) -> void:
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		if entry.get("effect") != effect:
			continue
		_entries.remove_at(i)
		var chip = entry.get("chip")
		if effect != null and is_instance_valid(effect):
			if effect.has_method("stop"):
				effect.call("stop")
			if free_effect:
				effect.queue_free()
		field_mod_stopped.emit(chip, effect)
		ExtensionHooks.notify_named("on_field_mod_stopped", [chip, effect])
		return

func _on_effect_exiting(effect: Node) -> void:
	_remove_entry(effect, false)

func _on_effect_finished(effect: Node) -> void:
	_remove_entry(effect, true)

func _on_game_over(_player_dead: bool) -> void:
	clear_all()

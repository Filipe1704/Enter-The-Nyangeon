extends Node

const HAVOC_ID := "havoc"

signal chips_changed(active_chips: Array, counts: Array, cap: int)
signal chip_assigned(index: int, count: int)
signal chip_released(index: int, count: int)

@export_category("Chip selection")
@export var active_chip_limit: int = 3
@export var chip_weight_initial: float = 1.0
@export var chip_weight_decay: float = 0.7
@export var chip_weight_min: float = 0.1
@export var chip_weight_boost: float = 0.5
@export var chip_weight_max: float = 4.0

@export_category("Enemy cap")
@export var chip_enemy_cap_base: int = 8
@export var chip_enemy_cap_growth: int = 2
@export var chip_enemy_cap_max: int = 40
@export var chip_enemy_cap_bonus_per_extra: int = 4

@export_category("Score")
@export var chip_score_bonus_per_chip: float = 0.03

@export_category("Buff")
@export var chip_buff_duration: float = 99999.0

var _selected_chips: Array[GameMode] = []
var _active_chips: Array[GameMode] = []
var _counts: Array[int] = []
var _weight_state: Dictionary = {}
var _cap := 0
var _active_count: int = 0
var _marked: Dictionary = {}
var _should_update_weights := false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("ChipManager")
	_rng.randomize()
	GameEvents.first_round_add.connect(_reset_run)
	GameEvents.round_end.connect(_on_round_end)
	_reset_run()

func _reset_run() -> void:
	_weight_state.clear()
	_selected_chips.clear()
	_active_chips.clear()
	_counts.clear()
	_marked.clear()
	_cap = 0
	_active_count = 0
	_should_update_weights = false
	chips_changed.emit([], [], 0)

func _on_round_end() -> void:
	if not _should_update_weights:
		return
	_update_weights_after_pick(_selected_chips, _active_chips)
	_should_update_weights = false

func prepare_round() -> void:
	if _should_update_weights:
		_update_weights_after_pick(_selected_chips, _active_chips)
		_should_update_weights = false
	_selected_chips = _load_selected_chip_modes()
	_active_chips.clear()
	_counts.clear()
	_marked.clear()
	_active_count = 0
	if active_chip_limit <= 0 or _selected_chips.is_empty():
		_cap = 0
		chips_changed.emit([], [], 0)
		return
	_should_update_weights = _selected_chips.size() > active_chip_limit
	if _should_update_weights:
		var picked := _pick_weighted_indices(_selected_chips, active_chip_limit)
		for index in picked:
			_active_chips.append(_selected_chips[index])
	else:
		for chip in _selected_chips:
			_active_chips.append(chip)
	_cap = _cap_for_round(maxi(1, int(PlayerData.now_round)))
	_counts.resize(_active_chips.size())
	for i in _counts.size():
		_counts[i] = 0
	chips_changed.emit(_active_chips.duplicate(), _counts.duplicate(), _cap)

func apply_to_enemy(enemy_body: Node, enemy_card: EnemyCard, is_boss: bool) -> bool:
	if enemy_body == null or enemy_card == null:
		return false
	if _active_chips.is_empty() or _cap <= 0 or _active_count >= _cap:
		return false
	if _marked.has(enemy_body.get_instance_id()):
		return false
	var is_boss_enemy := is_boss or enemy_card is BossCard
	var candidates: Array[int] = []
	var candidate_weights: Array[float] = []
	for i in _active_chips.size():
		var chip := _active_chips[i]
		if is_boss_enemy and not chip.chip_include_boss:
			continue
		if not _matches_target(chip, enemy_card):
			continue
		candidates.append(i)
		candidate_weights.append(_effective_weight(chip))
	if candidates.is_empty():
		return false
	var manager := BuffRouter.resolve_manager(enemy_body)
	if manager == null or not manager.has_method("apply_buff"):
		return false
	var pick := _pick_from_indices(candidates, candidate_weights)
	if pick < 0:
		return false
	var chip := _active_chips[pick]
	var source_id := "chip:" + chip.game_mode_id
	var buff_ids: Array[String] = []
	for buff in chip.chip_buffs:
		if buff == null:
			continue
		manager.apply_buff(buff, [1, 1.0, chip_buff_duration], source_id)
		if str(buff.id) != "":
			buff_ids.append(str(buff.id))
	_counts[pick] += 1
	_active_count += 1
	enemy_body.set_meta("chip_id", chip.game_mode_id)
	_marked[enemy_body.get_instance_id()] = {
		"index": pick,
		"chip_id": chip.game_mode_id,
		"buff_ids": buff_ids,
	}
	_watch_enemy(enemy_body, manager)
	chip_assigned.emit(pick, _counts[pick])
	return true

func _watch_enemy(enemy_body: Node, manager: Node) -> void:
	var stats = enemy_body.get("stats")
	if stats != null:
		var dead_cb := Callable(self, "_on_marked_enemy_dead").bind(enemy_body)
		if not stats.is_dead.is_connected(dead_cb):
			stats.is_dead.connect(dead_cb)
	var exit_cb := Callable(self, "_on_marked_enemy_exiting").bind(enemy_body)
	if not enemy_body.tree_exiting.is_connected(exit_cb):
		enemy_body.tree_exiting.connect(exit_cb)
	if manager != null and manager.has_signal("buff_expired"):
		var buff_cb := Callable(self, "_on_marked_buff_expired").bind(enemy_body, manager)
		if not manager.buff_expired.is_connected(buff_cb):
			manager.buff_expired.connect(buff_cb)

func _on_marked_enemy_dead(body: Node) -> void:
	_release_marked(body)

func _on_marked_enemy_exiting(body: Node) -> void:
	_release_marked(body)

func _on_marked_buff_expired(_buff: Buff, body: Node, manager: Node) -> void:
	if body == null or manager == null:
		return
	var id := body.get_instance_id()
	if not _marked.has(id):
		return
	var entry: Dictionary = _marked[id]
	var current = manager.get("current_buff")
	if current is Dictionary:
		for buff_id in entry["buff_ids"]:
			if current.has(buff_id):
				return
	_release_marked(body)

func _release_marked(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	if not _marked.has(id):
		return
	var entry: Dictionary = _marked[id]
	_marked.erase(id)
	var index := int(entry.get("index", -1))
	if index >= 0 and index < _counts.size():
		_counts[index] = maxi(0, _counts[index] - 1)
		chip_released.emit(index, _counts[index])
	_active_count = maxi(0, _active_count - 1)
	if body.has_meta("chip_id"):
		body.remove_meta("chip_id")

func get_active_chips() -> Array:
	return _active_chips.duplicate()

func get_chip_counts() -> Array:
	return _counts.duplicate()

func get_active_count() -> int:
	return _active_count

func get_round_cap() -> int:
	return _cap

func _cap_for_round(round_index: int) -> int:
	var base := clampi(
		chip_enemy_cap_base + chip_enemy_cap_growth * maxi(0, round_index - 1),
		0,
		chip_enemy_cap_max
	)
	var extra_count := maxi(0, _selected_chips.size() - maxi(0, active_chip_limit))
	return base + extra_count * maxi(0, chip_enemy_cap_bonus_per_extra)

func get_selected_chip_count() -> int:
	if not _selected_chips.is_empty():
		return int(_selected_chips.size())
	return _load_selected_chip_modes().size()

func get_score_multiplier() -> float:
	return 1.0 + maxf(0.0, chip_score_bonus_per_chip) * float(get_selected_chip_count())

func _load_selected_chip_modes() -> Array[GameMode]:
	if not PlayerData.game_mode.has(HAVOC_ID):
		return []
	var by_id: Dictionary = {}
	for mode in ModManager.get_base_game_modes():
		if mode is GameMode:
			by_id[mode.game_mode_id] = mode
	for mode in ModManager.get_content("game_modes"):
		if mode is GameMode:
			by_id[mode.game_mode_id] = mode
	var result: Array[GameMode] = []
	var seen: Dictionary = {}
	for id in PlayerData.game_mode:
		var key := str(id)
		if seen.has(key):
			continue
		seen[key] = true
		var mode = by_id.get(key, null)
		if mode is GameMode and mode.chip_enabled:
			result.append(mode)
	return result

func _effective_weight(chip: GameMode) -> float:
	if chip == null:
		return 0.0
	var state := float(_weight_state.get(chip.game_mode_id, chip_weight_initial))
	return maxf(0.0, chip.chip_weight) * maxf(0.0, state)

func _pick_weighted_indices(items: Array[GameMode], count: int) -> Array[int]:
	var result: Array[int] = []
	if count <= 0 or items.is_empty():
		return result
	var pool: Array[int] = []
	for i in items.size():
		pool.append(i)
	var weights: Array[float] = []
	weights.resize(pool.size())
	while result.size() < count and not pool.is_empty():
		var total := 0.0
		for i in pool.size():
			var weight := _effective_weight(items[pool[i]])
			weights[i] = weight
			total += weight
		var pick := 0
		if total <= 0.0:
			pick = _rng.randi_range(0, pool.size() - 1)
		else:
			var roll := _rng.randf() * total
			for i in pool.size():
				roll -= weights[i]
				if roll <= 0.0:
					pick = i
					break
		result.append(pool[pick])
		pool.remove_at(pick)
	return result

func _pick_from_indices(indices: Array[int], weights: Array[float]) -> int:
	if indices.is_empty():
		return -1
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, weight)
	if total <= 0.0:
		return indices[_rng.randi_range(0, indices.size() - 1)]
	var roll := _rng.randf() * total
	for i in indices.size():
		roll -= maxf(0.0, weights[i])
		if roll <= 0.0:
			return indices[i]
	return indices[indices.size() - 1]

func _update_weights_after_pick(selected: Array[GameMode], active: Array[GameMode]) -> void:
	var active_ids: Dictionary = {}
	for chip in active:
		active_ids[chip.game_mode_id] = true
	for chip in selected:
		var id := chip.game_mode_id
		var current := float(_weight_state.get(id, chip_weight_initial))
		if active_ids.has(id):
			_weight_state[id] = maxf(chip_weight_min, current * chip_weight_decay)
		else:
			_weight_state[id] = minf(chip_weight_max, current + chip_weight_boost)

func _matches_target(chip: GameMode, enemy_card: EnemyCard) -> bool:
	var ids := chip.chip_target_enemy_ids
	var tags := chip.chip_target_tags
	if ids.is_empty() and tags.is_empty():
		return true
	if not ids.is_empty() and ids.has(enemy_card.id):
		return true
	if not tags.is_empty():
		for tag in enemy_card.chip_tags:
			if tags.has(tag):
				return true
	return false

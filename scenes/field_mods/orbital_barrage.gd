extends FieldModEffect

const MARKER_SCENE: PackedScene = preload("res://scenes/effects/orbital_strike_marker.tscn")
const GOLIATH_PARTICLE_SCENE: PackedScene = preload("res://scenes/effects/goliath_cannon_particles.tscn")
const SLOW_BUFF: Buff = preload("res://resources/buff/player_buff/orbital_barrage_slow.tres")
const SLOW_VALUE: Array = [1, 0.5, 1.5] # [max_layer, 移速倍率, 持续秒数]；0.5 = 减速 50%
const SLOW_SOURCE_ID := "orbital_barrage"

signal strike_marker_spawned(id: int, point: Vector2, warning_seconds: float)
signal strike_marker_detonated(id: int)
signal strike_blast_fired(point: Vector2, blast_radius: float, damage_ratio: float)
signal strike_wave_ended

enum Phase { IDLE, ACTIVE }

@export_group("Timing")
@export var initial_delay_seconds: float = 2.0
@export var cooldown_seconds: float = 4.0
@export var warning_seconds: float = 4.0
@export var marker_spawn_interval_seconds: float = 1.2

@export_group("Strike")
@export var strike_radius: float = 80.0 # 仅用于落点最小间距（×1.5），不参与爆炸范围
@export var barrage_count: int = 6
@export var barrage_radius: float = 130.0
@export var blast_radius: float = 70.0
@export var barrage_gap_min_ticks: int = 1
@export var barrage_gap_max_ticks: int = 3
@export var goliath_particle_lifetime: float = 1.2
@export var damage_ratio: float = 0.10
@export var base_strikes: int = 1
@export var max_strikes: int = 4
@export var strike_step_rounds: int = 5
@export var target_offset_min: float = 16.0
@export var target_offset_max: float = 56.0

@export_group("Gold targeting")
@export var gold_target_enabled: bool = true
@export var gold_search_radius: float = 180.0 # 密度搜索半径（≈弹幕覆盖）
@export var gold_min_weight: float = 2.0 # 低于该密度视为“不密集”，回退玩家
@export var gold_pick_ratio: float = 0.8 # 得分 ≥ 最高分×比例 的候选进入随机池
@export var gold_coin_weight_cap: float = 10.0 # 单枚金币权重上限（防大额合并币独占）

var _phase := Phase.IDLE
var _phase_ticks := 0
var _idle_ticks := 0
var _all_cells: Array[Vector2i] = []
var _target_count := 0
var _target_spawned := 0
var _spawned_points: Array[Vector2] = []
var _active_strikes: Array[Dictionary] = []
var _barrage_events: Array[Dictionary] = []
var _next_spawn_tick := 0
var _next_strike_id := 0
var _barrage_shake_done := false
var _rng := RandomNumberGenerator.new()

func on_start() -> void:
	_rng.randomize()
	if not MapChunks.ensure_ready():
		push_warning("OrbitalBarrage: MapChunks is not ready")
		finish()
		return
	_all_cells = MapChunks.get_all_cells()
	if _all_cells.is_empty():
		finish()
		return
	_start_idle(initial_delay_seconds)

func on_stop() -> void:
	_clear_active_strikes()
	_target_count = 0
	_target_spawned = 0
	_spawned_points.clear()
	_barrage_events.clear()
	_barrage_shake_done = false
	_next_spawn_tick = 0
	_all_cells.clear()
	_phase = Phase.IDLE
	_phase_ticks = 0

func on_tick() -> void:
	_phase_ticks += 1
	if _phase == Phase.IDLE:
		if _phase_ticks >= maxi(1, _idle_ticks):
			_begin_wave()
	else:
		_tick_active()

func _start_idle(delay_seconds: float) -> void:
	_clear_active_strikes()
	_barrage_events.clear()
	_target_count = 0
	_target_spawned = 0
	_spawned_points.clear()
	_barrage_shake_done = false
	_next_spawn_tick = 0
	_phase = Phase.IDLE
	_phase_ticks = 0
	_idle_ticks = maxi(1, roundi(maxf(0.1, delay_seconds) * 10.0))

func _begin_wave() -> void:
	_target_count = _choose_target_count()
	if _target_count <= 0:
		_start_idle(cooldown_seconds)
		return
	_active_strikes.clear()
	_barrage_events.clear()
	_target_spawned = 0
	_spawned_points.clear()
	_barrage_shake_done = false
	_phase = Phase.ACTIVE
	_phase_ticks = 0
	_next_spawn_tick = 0
	_spawn_next_target()
	_next_spawn_tick = _marker_spawn_ticks()

func _tick_active() -> void:
	if _target_spawned < _target_count and _phase_ticks >= _next_spawn_tick:
		_spawn_next_target()
		_next_spawn_tick = _phase_ticks + _marker_spawn_ticks()
	_detonate_due_strikes()
	_process_barrage_events()
	if _target_spawned >= _target_count and _active_strikes.is_empty() and _barrage_events.is_empty():
		strike_wave_ended.emit()
		_start_idle(cooldown_seconds)

func _marker_spawn_ticks() -> int:
	return maxi(1, roundi(maxf(0.1, marker_spawn_interval_seconds) * 10.0))

func get_orbital_network_state() -> Dictionary:
	var markers: Array = []
	for strike in _active_strikes:
		markers.append({
			"id": int(strike.get("id", -1)),
			"point": strike.get("point", Vector2.ZERO),
			"remaining": maxf(0.0, float(int(strike.get("detonate_tick", _phase_ticks)) - _phase_ticks) * 0.1),
		})
	return {"markers": markers} if not markers.is_empty() else {}

func _spawn_next_target() -> void:
	if _target_spawned >= _target_count:
		return
	var point := _choose_target_point(_target_spawned, _spawned_points)
	_target_spawned += 1
	_spawned_points.append(point)
	var marker: OrbitalStrikeMarker
	var parent := _marker_parent()
	if parent != null:
		marker = MARKER_SCENE.instantiate() as OrbitalStrikeMarker
		if marker != null:
			parent.add_child(marker)
			marker.global_position = point
			marker.setup(warning_seconds)
			marker.start_countdown()
	var strike_id := _next_strike_id
	_next_strike_id += 1
	_active_strikes.append({
		"id": strike_id,
		"point": point,
		"detonate_tick": _phase_ticks + maxi(1, roundi(warning_seconds * 10.0)),
		"marker": marker,
	})
	strike_marker_spawned.emit(strike_id, point, warning_seconds)
	SoundManager.play_sfx_throttled("BlipSounds1")

func _detonate_due_strikes() -> void:
	var index := 0
	while index < _active_strikes.size():
		var strike: Dictionary = _active_strikes[index]
		if int(strike["detonate_tick"]) <= _phase_ticks:
			_detonate_strike(strike)
			_active_strikes.remove_at(index)
		else:
			index += 1

func _detonate_strike(strike: Dictionary) -> void:
	var strike_id := int(strike.get("id", -1))
	var marker: OrbitalStrikeMarker = strike.get("marker")
	if marker != null and is_instance_valid(marker):
		marker.play_exit()
	strike_marker_detonated.emit(strike_id)
	var point: Vector2 = strike["point"]
	var min_gap := maxi(1, mini(barrage_gap_min_ticks, barrage_gap_max_ticks))
	var max_gap := maxi(min_gap, barrage_gap_max_ticks)
	var fire_tick := _phase_ticks + _rng.randi_range(0, max_gap)
	for _index in maxi(1, barrage_count):
		fire_tick += _rng.randi_range(min_gap, max_gap)
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(0.0, barrage_radius)
		var blast_point := point + Vector2(cos(angle), sin(angle)) * distance
		_barrage_events.append({"tick": fire_tick, "point": blast_point})

func _process_barrage_events() -> void:
	var index := 0
	while index < _barrage_events.size():
		var event: Dictionary = _barrage_events[index]
		if int(event["tick"]) > _phase_ticks:
			index += 1
			continue
		var point: Vector2 = event["point"]
		_fire_blast(point)
		_barrage_events.remove_at(index)

func _fire_blast(point: Vector2) -> void:
	_spawn_goliath_blast(point)
	_apply_damage(point, blast_radius)
	strike_blast_fired.emit(point, blast_radius, damage_ratio)
	SoundManager.play_sfx_throttled("ExplosionSounds2", 60)
	if not _barrage_shake_done:
		_barrage_shake_done = true
		GameEvents.emit_shake_screen(6, 3.0, 0.16)

func _choose_target_count() -> int:
	var players := _alive_players()
	var count := maxi(base_strikes, mini(players.size(), max_strikes))
	count = maxi(count, 1 + floori(float(maxi(1, int(PlayerData.now_round)) - 1) / float(maxi(1, strike_step_rounds))))
	return mini(count, max_strikes)

func _choose_target_point(index: int, existing_points: Array[Vector2]) -> Vector2:
	var gold := _choose_gold_target(existing_points)
	if gold.has("point"):
		return gold["point"]
	var players := _alive_players()
	var point := Vector2.ZERO
	for _attempt in 8:
		var base := _player_position(players, index)
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(target_offset_min, target_offset_max)
		point = base + Vector2(cos(angle), sin(angle)) * distance
		point = MapBounds.nearest_inside(point)
		if _is_separated(point, existing_points):
			break
	return point

func _is_separated(point: Vector2, existing_points: Array[Vector2]) -> bool:
	for existing in existing_points:
		if existing.distance_to(point) < strike_radius * 1.5:
			return false
	return true

# 金币密集优先：选出密度最高的落点；无合格金币时返回空字典，由调用方回退到玩家追踪。
func _choose_gold_target(existing_points: Array[Vector2]) -> Dictionary:
	if not gold_target_enabled:
		return {}
	var candidates := _score_gold_candidates(_collect_gold_samples())
	if candidates.is_empty():
		return {}
	var best_score := float(candidates[0]["score"])
	if best_score < gold_min_weight:
		return {}
	var pool: Array = []
	for candidate in candidates:
		if float(candidate["score"]) < best_score * gold_pick_ratio:
			break
		pool.append(candidate)
	# 金币优先：全部候选都离已有落点太近时，仍取最密集点，不转去打玩家。
	var top_point: Vector2 = candidates[0]["point"]
	var top_angle := _rng.randf_range(0.0, TAU)
	var top_distance := _rng.randf_range(0.0, target_offset_min)
	var fallback := MapBounds.nearest_inside(top_point + Vector2(cos(top_angle), sin(top_angle)) * top_distance)
	while not pool.is_empty():
		var chosen_index := _pick_weighted_candidate_index(pool)
		var point: Vector2 = pool[chosen_index]["point"]
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(0.0, target_offset_min)
		point = MapBounds.nearest_inside(point + Vector2(cos(angle), sin(angle)) * distance)
		if _is_separated(point, existing_points):
			return {"point": point}
		pool.remove_at(chosen_index)
	return {"point": fallback}

func _pick_weighted_candidate_index(pool: Array) -> int:
	var total := 0.0
	for candidate in pool:
		total += maxf(0.0, float(candidate["score"]))
	if total <= 0.0:
		return _rng.randi_range(0, maxi(0, pool.size() - 1))
	var roll := _rng.randf() * total
	for index in pool.size():
		roll -= maxf(0.0, float(pool[index]["score"]))
		if roll <= 0.0:
			return index
	return pool.size() - 1

# 只统计“地上的金币”：回池、已被吸走、抛物线飞行中的都不算。
func _collect_gold_samples() -> Array:
	var samples: Array = []
	if CoinManager == null:
		return samples
	for coin in CoinManager.get_active_coins():
		if coin == null or not is_instance_valid(coin) or not coin.is_inside_tree():
			continue
		if int(coin.get("is_idle")) == 1:
			continue
		if bool(coin.get("pick_up")):
			continue
		if not bool(coin.get("can_pick")):
			continue
		var value := int(coin.get("coin"))
		var body := coin as Node2D
		if value <= 0 or body == null:
			continue
		samples.append({
			"pos": body.global_position,
			"weight": _gold_coin_weight(value),
		})
	return samples

func _gold_coin_weight(value: int) -> float:
	return clampf(float(value), 1.0, maxf(1.0, gold_coin_weight_cap))

# 世界空间分桶求权重质心，再按半径内金币权重线性衰减打分（纯函数，便于单测）。
func _score_gold_candidates(samples: Array) -> Array:
	if samples.is_empty():
		return []
	var bucket_size := maxf(32.0, gold_search_radius * 0.5)
	var buckets: Dictionary = {}
	for sample in samples:
		var pos: Vector2 = sample["pos"]
		var weight := float(sample["weight"])
		if weight <= 0.0:
			continue
		var key := Vector2i(floori(pos.x / bucket_size), floori(pos.y / bucket_size))
		var bucket: Dictionary = buckets.get(key, {})
		if bucket.is_empty():
			bucket = {"sum": Vector2.ZERO, "weight": 0.0}
			buckets[key] = bucket
		var sum: Vector2 = bucket["sum"]
		bucket["sum"] = sum + pos * weight
		bucket["weight"] = float(bucket["weight"]) + weight
	var radius := maxf(1.0, gold_search_radius)
	var radius_sq := radius * radius
	var candidates: Array = []
	for bucket in buckets.values():
		var bucket_weight := float(bucket["weight"])
		if bucket_weight <= 0.0:
			continue
		var sum: Vector2 = bucket["sum"]
		var center := sum / bucket_weight
		var score := 0.0
		for sample in samples:
			var sample_pos: Vector2 = sample["pos"]
			var distance_sq := center.distance_squared_to(sample_pos)
			if distance_sq > radius_sq:
				continue
			score += float(sample["weight"]) * (1.0 - sqrt(distance_sq) / radius)
		candidates.append({"point": center, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return candidates

func _alive_players() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var seen: Dictionary = {}
	for group_name in ["Player", "RemotePlayer"]:
		for player in get_tree().get_nodes_in_group(group_name):
			if player == null or not is_instance_valid(player) or not player.is_inside_tree():
				continue
			var player_id := player.get_instance_id()
			if seen.has(player_id):
				continue
			var body := player as Node2D
			if body == null:
				continue
			if player.get("is_downed") == true:
				continue
			var stats = player.get("stats")
			if stats == null or stats.hp <= 0:
				continue
			seen[player_id] = true
			result.append(body)
	return result

func _player_position(players: Array[Node2D], index: int) -> Vector2:
	if not players.is_empty():
		return players[index % players.size()].global_position
	if _all_cells.is_empty():
		return Vector2.ZERO
	var cell := _all_cells[_rng.randi_range(0, _all_cells.size() - 1)]
	return MapChunks.get_cell_world(cell)

func _apply_damage(point: Vector2, radius: float) -> void:
	var radius_sq := radius * radius
	for player in get_tree().get_nodes_in_group("Player"):
		if _damage_entity(player, point, radius_sq):
			_apply_player_slow(player)
	for enemy in PoolManager.get_active_enemies():
		_damage_entity(enemy, point, radius_sq)

func _damage_entity(entity: Node, point: Vector2, radius_sq: float) -> bool:
	if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
		return false
	if entity.get("is_downed") == true:
		return false
	var stats = entity.get("stats")
	if stats == null or stats.hp <= 0:
		return false
	var body := entity as Node2D
	if body == null or body.global_position.distance_squared_to(point) > radius_sq:
		return false
	var health = entity.get("health_component")
	if health == null or not health.has_method("take_damage"):
		return false
	var amount := maxi(1, roundi(float(stats.max_hp) * damage_ratio))
	var data := DamageData.make({
		"damage": amount,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.NEUTRAL,
		"flags": GameTags.TRUE_DAMAGE,
		"node": self,
		"center": point,
	})
	health.call("take_damage", data)
	return true

# 命中减速只对玩家生效（敌人不挂）；重复命中由 source_refcount 刷新时长、不叠层。
func _apply_player_slow(player: Node) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	if player.get("is_downed") == true:
		return
	var stats = player.get("stats")
	if stats == null or stats.hp <= 0:
		return
	BuffRouter.apply_buff(player, SLOW_BUFF, SLOW_VALUE, SLOW_SOURCE_ID)

# 供联机 mod 复用同一份减速数值（host 下发，客机本机给真实玩家挂 buff）。
func get_player_slow_config() -> Dictionary:
	return {
		"buff_path": SLOW_BUFF.resource_path,
		"value": SLOW_VALUE,
		"source_id": SLOW_SOURCE_ID,
	}

func _spawn_goliath_blast(point: Vector2) -> void:
	var parent := _fx_parent()
	if parent == null:
		return
	var blast := GOLIATH_PARTICLE_SCENE.instantiate() as GoliathCannonParticles
	if blast == null:
		return
	blast.z_index = 4
	parent.add_child(blast)
	blast.global_position = point
	blast.rotation = _rng.randf_range(0.0, TAU)
	var scale := _rng.randf_range(1.0, 1.15)
	blast.scale = Vector2(scale, scale)
	blast.play_at(blast_radius)
	var lifetime := get_tree().create_timer(maxf(0.1, goliath_particle_lifetime))
	lifetime.timeout.connect(func() -> void:
		if blast != null and is_instance_valid(blast):
			blast.queue_free()
	)

func _marker_parent() -> Node:
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer != null:
		return layer
	var field_root := get_tree().get_first_node_in_group("FieldModRoot")
	if field_root != null and field_root.get_parent() != null:
		return field_root.get_parent()
	return get_parent()

func _fx_parent() -> Node:
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer != null:
		return layer
	return get_parent()

func _clear_active_strikes() -> void:
	for strike in _active_strikes:
		var marker: OrbitalStrikeMarker = strike.get("marker")
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
	_active_strikes.clear()

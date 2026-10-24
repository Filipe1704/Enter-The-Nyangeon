extends FieldModEffect

const CHUNK_SIZE := Vector2i(4, 4)
const SLOW_BUFF: Buff = preload("res://resources/buff/player_buff/corruption_field_slow.tres")
const FOG_FIELD_SCENE: PackedScene = preload("res://scenes/effects/fog/fog_field.tscn")

enum Phase { IDLE, WARNING, ACTIVE }

signal wave_started(cells: PackedVector2Array, fog_points: PackedVector2Array)
signal wave_activated(cells: PackedVector2Array, fog_points: PackedVector2Array)
signal wave_ended

@export_group("Side region")
@export var min_walkable_ratio: float = 0.0

@export_group("Growth")
@export_range(0.0, 1.0) var side_ratio_start: float = 0.2
@export_range(0.0, 1.0) var side_ratio_step: float = 0.05
@export var side_ratio_step_rounds: int = 3
@export_range(0.0, 1.0) var side_ratio_max: float = 0.4

@export_group("Poison fog")
@export var fog_settings: FogSettings
@export var fog_density: float = 1.0
@export var fog_emitter_spacing: float = 64.0
@export var corruption_interval_ticks: int = 4
@export var corruption_ratio: float = 0.03
@export var slow_value: Array[float] = [1.0, 0.7, 0.5]

@export_group("Timing")
@export var interval_ticks: int = 50
@export var warning_ticks: int = 20
@export var active_ticks: int = 100

@onready var warning_layer: TileMapLayer = $WarningLayer

var _grid: MapChunkGrid
var _all_cells: Array[Vector2i] = []
var _side_chunks: Array = [[], [], [], []]
var _side_distances: Array = [[], [], [], []]
var _edges: Array = []
var _best_depth := -1.0
var _band_cells: Array[Vector2i] = []
var _band_cell_set: Dictionary = {}
var _chunks: Array[MapChunk] = []
var _fog_field: FogField
var _affected_players: Dictionary = {}
var _phase := Phase.IDLE
var _phase_ticks := 0
var _rng := RandomNumberGenerator.new()
var _side_order: Array[int] = []
var _last_side := -1
var _current_side := -1
var is_remote := false
var _remote_fog_points: PackedVector2Array = []
var _source_id := ""
var _bounds_source: StringName = &""

func on_start() -> void:
	_rng.randomize()
	_source_id = "corruption_spread:%d" % get_instance_id()
	if warning_layer == null:
		push_warning("CorruptionSpreadEffect: WarningLayer is missing")
		finish()
		return
	if fog_settings == null:
		push_warning("CorruptionSpreadEffect: fog_settings is missing")
		finish()
		return
	if not MapChunks.ensure_ready():
		push_warning("CorruptionSpreadEffect: MapChunks is not ready")
		finish()
		return
	_bounds_source = MapChunks.get_boundary_source()
	if is_remote:
		_start_interval()
		return
	_grid = MapChunks.get_grid(CHUNK_SIZE)
	if _grid == null:
		push_warning("CorruptionSpreadEffect: chunk grid is not ready")
		finish()
		return
	_all_cells = MapChunks.get_all_cells()
	if _all_cells.is_empty():
		finish()
		return
	_build_edge_data()
	var has_edges := false
	for side in 4:
		if not _side_chunks[side].is_empty():
			has_edges = true
			break
	if not has_edges:
		push_warning("CorruptionSpreadEffect: no edge chunks")
		finish()
		return
	_side_order.clear()
	_last_side = -1
	_current_side = -1
	_start_interval()

func on_stop() -> void:
	_clear_warning()
	_clear_fog()
	_clear_affected_players()
	_band_cells.clear()
	_band_cell_set.clear()
	_chunks.clear()
	_side_chunks = [[], [], [], []]
	_side_distances = [[], [], [], []]
	_edges.clear()
	_best_depth = -1.0
	_side_order.clear()
	_last_side = -1
	_current_side = -1
	_remote_fog_points.clear()
	_grid = null
	_bounds_source = &""

func on_tick() -> void:
	_phase_ticks += 1
	if _phase == Phase.IDLE:
		if not is_remote and _phase_ticks >= maxi(1, interval_ticks):
			_begin_wave()
	elif _phase == Phase.WARNING:
		if _phase_ticks >= maxi(1, warning_ticks):
			_activate_wave()
	elif _phase == Phase.ACTIVE:
		_refresh_affected_players()
		if corruption_interval_ticks > 0 and _phase_ticks % corruption_interval_ticks == 0:
			_apply_corruption()
		if _phase_ticks >= maxi(1, active_ticks):
			_finish_wave()

func _prepare_wave() -> void:
	_band_cells.clear()
	_band_cell_set.clear()
	_chunks.clear()
	_current_side = -1
	_refresh_bounds_if_needed()
	if _grid == null:
		return
	var target_cells := maxi(1, roundi(float(_all_cells.size()) * _ratio_for_round()))
	for _attempt in 4:
		var side := _next_side()
		var selected := _select_side_chunks_by_area(side, target_cells)
		if selected.is_empty():
			continue
		var cells := _collect_cells_by_depth(side, selected, _best_depth)
		if cells.is_empty():
			continue
		var cell_set: Dictionary = {}
		for cell in cells:
			cell_set[cell] = true
		_chunks = selected
		_band_cells = cells
		_band_cell_set = cell_set
		_current_side = side
		return

# 首帧若用 SpawnMap 兜底边界构建，后续波次在边界切到 walls 时自动重建 cells / 块 / 边数据。
func _refresh_bounds_if_needed() -> void:
	var source := MapChunks.get_boundary_source()
	if source == _bounds_source:
		return
	_bounds_source = source
	if not MapChunks.ensure_ready():
		return
	_all_cells = MapChunks.get_all_cells()
	_grid = MapChunks.get_grid(CHUNK_SIZE)
	if _grid == null or _all_cells.is_empty():
		return
	_build_edge_data()

func _select_side_chunks_by_area(side: int, target_cells: int) -> Array[MapChunk]:
	var selected: Array[MapChunk] = []
	var side_chunks: Array = _side_chunks[side]
	var side_distances: Array = _side_distances[side]
	if side_chunks.is_empty() or target_cells <= 0:
		return selected
	var order: Array[int] = []
	for i in side_chunks.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return float(side_distances[a]) < float(side_distances[b])
	)
	var best_depth := -1.0
	var best_diff := 1 << 30
	var cumulative := 0
	var index := 0
	while index < order.size():
		var depth := float(side_distances[order[index]])
		var group_cells := 0
		while index < order.size() and is_equal_approx(float(side_distances[order[index]]), depth):
			group_cells += (side_chunks[order[index]] as MapChunk).cells.size()
			index += 1
		cumulative += group_cells
		var diff := absi(cumulative - target_cells)
		if diff < best_diff:
			best_diff = diff
			best_depth = depth
		if cumulative >= target_cells:
			break
	if best_depth < 0.0:
		_best_depth = -1.0
		return selected
	for i in side_chunks.size():
		if float(side_distances[i]) <= best_depth + 0.001:
			selected.append(side_chunks[i])
	_best_depth = best_depth
	return selected

func _collect_cells_by_depth(side: int, chunks: Array[MapChunk], depth: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if side < 0 or side >= _edges.size():
		return result
	var edge: Dictionary = _edges[side]
	var edge_start: Vector2 = edge["start"]
	var edge_end: Vector2 = edge["end"]
	for chunk in chunks:
		if chunk == null:
			continue
		for cell in chunk.cells:
			var world := MapChunks.get_cell_world(cell)
			var closest := Geometry2D.get_closest_point_to_segment(world, edge_start, edge_end)
			if world.distance_to(closest) <= depth + 0.001:
				result.append(cell)
	return result

func _ratio_for_round() -> float:
	var round_num := maxi(1, int(PlayerData.now_round))
	var steps := floori(float(round_num - 1) / float(maxi(1, side_ratio_step_rounds)))
	return clampf(side_ratio_start + side_ratio_step * float(steps), side_ratio_start, side_ratio_max)

func _next_side() -> int:
	if _side_order.is_empty():
		_refill_side_order()
	var side := int(_side_order.pop_front())
	_last_side = side
	return side

func _refill_side_order() -> void:
	var order: Array[int] = [0, 1, 2, 3]
	_shuffle(order)
	if _last_side >= 0 and order.size() > 1 and order[0] == _last_side:
		var swap_index := _rng.randi_range(1, order.size() - 1)
		var first := order[0]
		order[0] = order[swap_index]
		order[swap_index] = first
	_side_order = order

func _build_edge_data() -> void:
	_side_chunks = [[], [], [], []]
	_side_distances = [[], [], [], []]
	_edges = []
	if _grid == null:
		return
	var polygon := MapChunks.get_walkable_polygon()
	if polygon.size() != 4:
		push_warning("CorruptionSpreadEffect: expected a four-edge map hull")
		return
	for side in 4:
		var start := polygon[side]
		var end := polygon[(side + 1) % 4]
		var direction: Vector2 = (end - start).normalized()
		_edges.append({
			"start": start,
			"end": end,
			"direction": direction,
			"length": start.distance_to(end),
		})
	for chunk in _grid.get_chunks(min_walkable_ratio):
		var center := chunk.world_center
		for side in 4:
			var edge: Dictionary = _edges[side]
			var edge_start: Vector2 = edge["start"]
			var edge_end: Vector2 = edge["end"]
			var direction: Vector2 = edge["direction"]
			var along := (center - edge_start).dot(direction)
			if along < 0.0 or along > float(edge["length"]):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(center, edge_start, edge_end)
			_side_chunks[side].append(chunk)
			_side_distances[side].append(center.distance_to(closest))

func _start_warning() -> void:
	_clear_fog()
	_clear_affected_players()
	_clear_warning()
	if warning_layer == null:
		finish()
		return
	for cell in _band_cells:
		warning_layer.set_cell(cell, 0, Vector2i.ZERO)
	warning_layer.visible = true
	_phase = Phase.WARNING
	_phase_ticks = 0
	if not is_remote:
		wave_started.emit(_pack_band_cells(), _pack_fog_points())

func _activate_wave() -> void:
	_clear_warning()
	_clear_fog()
	if fog_settings == null:
		finish()
		return
	_spawn_fog()
	_phase = Phase.ACTIVE
	_phase_ticks = 0
	SoundManager.play_sfx("CorruptionSpawn")
	if not is_remote:
		wave_activated.emit(_pack_band_cells(), _pack_fog_points())

func _spawn_fog() -> void:
	var parent := _fog_parent()
	if parent == null:
		return
	var field := FOG_FIELD_SCENE.instantiate() as FogField
	if field == null:
		return
	parent.add_child(field)
	field.set_cloud_parent(parent)
	field.settings = fog_settings
	field.density = fog_density
	field.emitter_spacing = fog_emitter_spacing
	var points: Array[Vector2] = []
	if not _remote_fog_points.is_empty():
		for p in _remote_fog_points:
			points.append(p)
	else:
		for chunk in _chunks:
			if chunk != null:
				points.append(chunk.world_center)
	field.emit_points(points)
	_fog_field = field

func _pack_band_cells() -> PackedVector2Array:
	var out := PackedVector2Array()
	for cell in _band_cells:
		out.append(Vector2(cell.x, cell.y))
	return out

func _pack_fog_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not _remote_fog_points.is_empty():
		out.append_array(_remote_fog_points)
		return out
	for chunk in _chunks:
		if chunk != null:
			out.append(chunk.world_center)
	return out

func get_network_state() -> Dictionary:
	if _phase == Phase.IDLE or _band_cells.is_empty():
		return {}
	return {
		"cells": _pack_band_cells(),
		"points": _pack_fog_points(),
		"phase": int(_phase),
		"phase_ticks": _phase_ticks,
	}

func apply_remote_wave(cells: PackedVector2Array, fog_points: PackedVector2Array, phase: int = Phase.WARNING, phase_ticks: int = 0) -> void:
	_band_cells.clear()
	_band_cell_set.clear()
	for v in cells:
		var cell := Vector2i(int(v.x), int(v.y))
		_band_cells.append(cell)
		_band_cell_set[cell] = true
	_remote_fog_points = fog_points.duplicate()
	var target_phase := clampi(int(phase), int(Phase.IDLE), int(Phase.ACTIVE))
	if target_phase == Phase.IDLE:
		_start_interval()
		return
	if target_phase == Phase.ACTIVE:
		_start_warning()
		_activate_wave()
	else:
		_start_warning()
	_phase_ticks = maxi(0, phase_ticks)

func _fog_parent() -> Node:
	var field_root := get_tree().get_first_node_in_group("FieldModRoot")
	if field_root != null and field_root.get_parent() != null:
		return field_root.get_parent()
	return get_parent()

func _start_interval() -> void:
	_clear_warning()
	_clear_fog()
	_band_cells.clear()
	_band_cell_set.clear()
	_remote_fog_points.clear()
	_phase = Phase.IDLE
	_phase_ticks = 0

func _begin_wave() -> void:
	_prepare_wave()
	if _band_cells.is_empty():
		push_warning("CorruptionSpreadEffect: no valid poison fog band")
		finish()
		return
	_start_warning()

func _finish_wave() -> void:
	_clear_affected_players()
	_clear_fog()
	_start_interval()
	if not is_remote:
		wave_ended.emit()

func _clear_warning() -> void:
	if warning_layer == null:
		return
	warning_layer.clear()
	warning_layer.visible = false

func _clear_fog() -> void:
	if _fog_field != null and is_instance_valid(_fog_field):
		_fog_field.fade_out()
	_fog_field = null

func _refresh_affected_players() -> void:
	var current: Dictionary = {}
	for player in get_tree().get_nodes_in_group("Player"):
		if player == null or not is_instance_valid(player):
			continue
		if player.get("is_downed") == true:
			continue
		var stats = player.get("stats")
		if stats == null or stats.hp <= 0:
			continue
		var cell := MapChunks.world_to_cell(player.global_position)
		if not _band_cell_set.has(cell):
			continue
		BuffRouter.apply_buff(player, SLOW_BUFF, slow_value, _source_id)
		current[player] = true
	for player in _affected_players.keys():
		if current.has(player):
			continue
		if player != null and is_instance_valid(player):
			BuffRouter.remove_source(player, SLOW_BUFF, _source_id)
	_affected_players = current

func _apply_corruption() -> void:
	for player in _affected_players.keys():
		if player == null or not is_instance_valid(player):
			continue
		var stats = player.get("stats")
		if stats == null or stats.hp <= 0:
			continue
		stats.add_corruption(maxi(1, roundi(float(stats.max_hp) * corruption_ratio)))

func _clear_affected_players() -> void:
	for player in _affected_players.keys():
		if player != null and is_instance_valid(player):
			BuffRouter.remove_source(player, SLOW_BUFF, _source_id)
	_affected_players.clear()

func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp

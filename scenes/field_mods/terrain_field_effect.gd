class_name TerrainFieldEffect
extends FieldModEffect

@export_group("Chunks")
@export var chunk_size: Vector2i = Vector2i(4, 4)
@export var chunk_count: int = 3
@export_range(0.0, 1.0) var chunk_ratio: float = 0.0
@export var min_walkable_ratio: float = 0.5
@export var avoid_portal_chunks: bool = true
@export var avoid_spawnable_chunks: bool = false
@export var avoid_player_start_radius: float = 0.0
@export var allow_overlap: bool = false

@export_group("Overlay")
@export var overlay_tile_set: TileSet
@export var overlay_source_id: int = 0
@export var overlay_atlas_coords: Vector2i = Vector2i.ZERO
@export var overlay_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var overlay_z_index: int = -1

@export_group("Timing")
@export var tick_interval: int = 5
@export var duration_ticks: int = 0

var chunks: Array[MapChunk] = []

var _grid: MapChunkGrid
var _cells: Dictionary = {}
var _overlay: TileMapLayer
var _reserved_source_id := ""
var _tick_count := 0

func on_start() -> void:
	if chunk_count <= 0 and chunk_ratio <= 0.0:
		finish()
		return
	_reserved_source_id = "terrain:%d" % get_instance_id()
	_grid = MapChunks.get_grid(chunk_size)
	if _grid == null:
		push_warning("TerrainFieldEffect: MapChunks is not ready")
		finish()
		return
	chunks = _pick_terrain_chunks()
	if chunks.is_empty():
		push_warning("TerrainFieldEffect: no eligible chunks")
		finish()
		return
	if not allow_overlap:
		MapChunks.reserve_cells(_reserved_source_id, _reservation_cells())
	for chunk in chunks:
		for cell in chunk.cells:
			_cells[cell] = true
	_build_overlay()
	_tick_count = 0
	on_terrain_start()

func on_stop() -> void:
	on_terrain_stop()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if _reserved_source_id != "" and not allow_overlap:
		MapChunks.release_cells(_reserved_source_id)
	_reserved_source_id = ""
	_grid = null
	_cells.clear()
	chunks.clear()
	_tick_count = 0

func _pick_terrain_chunks() -> Array[MapChunk]:
	if _grid == null:
		return []
	var count := chunk_count
	if chunk_ratio > 0.0:
		var available := _grid.get_chunks(min_walkable_ratio)
		count = maxi(1, int(ceil(float(available.size()) * chunk_ratio)))
	var exclude: Array = [] if allow_overlap else MapChunks.get_reserved_cells()
	var player := _find_player()
	return _grid.pick_chunks(
		count,
		exclude,
		min_walkable_ratio,
		null,
		func(chunk: MapChunk) -> bool: return _allow_chunk(chunk, player)
	)

func _reservation_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for chunk in chunks:
		out.append_array(chunk.cells)
	return out

func on_tick() -> void:
	_tick_count += 1
	if duration_ticks > 0 and _tick_count >= duration_ticks:
		finish()
		return
	if tick_interval > 1 and _tick_count % tick_interval != 0:
		return
	on_terrain_tick()

func get_terrain_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _cells.keys():
		if cell is Vector2i:
			out.append(cell)
	return out

func get_terrain_source_id() -> String:
	return _reserved_source_id

func get_overlay() -> TileMapLayer:
	return _overlay

func is_body_in_terrain(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	return _cells.has(MapChunks.world_to_cell(body.global_position))

func on_terrain_start() -> void:
	pass

func on_terrain_stop() -> void:
	pass

func on_terrain_tick() -> void:
	pass

func _build_overlay() -> void:
	if overlay_tile_set == null:
		return
	_overlay = TileMapLayer.new()
	_overlay.name = "TerrainOverlay"
	_overlay.tile_set = overlay_tile_set
	_overlay.z_index = overlay_z_index
	_overlay.modulate = overlay_color
	_overlay.y_sort_enabled = false
	add_child(_overlay)
	for cell in _cells.keys():
		if cell is Vector2i:
			_overlay.set_cell(cell, overlay_source_id, overlay_atlas_coords)

func _find_player() -> Node2D:
	var player := get_tree().get_first_node_in_group("Player")
	return player as Node2D

func _allow_chunk(chunk: MapChunk, player: Node2D) -> bool:
	if chunk == null:
		return false
	if avoid_portal_chunks and chunk.portal_cell_count > 0:
		return false
	if avoid_spawnable_chunks and chunk.spawnable_cell_count > 0:
		return false
	if avoid_player_start_radius > 0.0 and player != null and is_instance_valid(player):
		for cell in chunk.cells:
			if MapChunks.get_cell_world(cell).distance_to(player.global_position) < avoid_player_start_radius:
				return false
	return true

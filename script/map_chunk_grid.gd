class_name MapChunkGrid
extends RefCounted

var size: Vector2i
var chunks: Dictionary = {}
var _cell_to_chunk: Dictionary = {}

func _init(p_size: Vector2i) -> void:
	size = Vector2i(maxi(1, p_size.x), maxi(1, p_size.y))

func build(cells: Array, cell_world: Callable, spawnable: Dictionary, portal: Dictionary) -> void:
	chunks.clear()
	_cell_to_chunk.clear()
	for cell in cells:
		if not (cell is Vector2i):
			continue
		var key := _chunk_key(cell)
		var chunk: MapChunk = chunks.get(key, null)
		if chunk == null:
			chunk = MapChunk.new(key, size)
			chunks[key] = chunk
		chunk.cells.append(cell)
		_cell_to_chunk[cell] = key
	for chunk in chunks.values():
		if chunk == null or chunk.cells.is_empty():
			continue
		var center_sum := Vector2.ZERO
		for cell in chunk.cells:
			var world = cell_world.call(cell)
			if world is Vector2:
				center_sum += world
			if spawnable.has(cell):
				chunk.spawnable_cell_count += 1
			if portal.has(cell):
				chunk.portal_cell_count += 1
		chunk.world_center = center_sum / float(chunk.cells.size())
		chunk.walkable_ratio = float(chunk.cells.size()) / float(size.x * size.y)

func get_chunks(min_ratio: float = 0.5) -> Array[MapChunk]:
	var out: Array[MapChunk] = []
	for chunk in chunks.values():
		if chunk is MapChunk and chunk.walkable_ratio + 0.0001 >= min_ratio:
			out.append(chunk)
	out.sort_custom(func(a: MapChunk, b: MapChunk) -> bool:
		if a.coords.x == b.coords.x:
			return a.coords.y < b.coords.y
		return a.coords.x < b.coords.x
	)
	return out

func pick_chunks(count: int, exclude_cells: Array = [], min_ratio: float = 0.5, rng: RandomNumberGenerator = null, allow: Callable = Callable()) -> Array[MapChunk]:
	if count <= 0:
		return []
	var excluded: Dictionary = {}
	for cell in exclude_cells:
		if cell is Vector2i:
			excluded[cell] = true
	var pool: Array[MapChunk] = []
	for chunk in get_chunks(min_ratio):
		if _chunk_overlaps(chunk, excluded):
			continue
		if allow.is_valid() and not bool(allow.call(chunk)):
			continue
		pool.append(chunk)
	var result: Array[MapChunk] = []
	var picker := RandomNumberGenerator.new() if rng == null else rng
	if rng == null:
		picker.randomize()
	while result.size() < count and not pool.is_empty():
		var index := picker.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result

func get_chunk_cells(chunk: MapChunk) -> Array[Vector2i]:
	if chunk == null:
		return []
	return chunk.cells.duplicate()

func cell_to_chunk(cell: Vector2i) -> Vector2i:
	return _cell_to_chunk.get(cell, Vector2i(2147483647, 2147483647))

func get_chunk(coords: Vector2i) -> MapChunk:
	return chunks.get(coords, null)

func _chunk_key(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(size.x)),
		floori(float(cell.y) / float(size.y))
	)

func _chunk_overlaps(chunk: MapChunk, excluded: Dictionary) -> bool:
	if excluded.is_empty():
		return false
	for cell in chunk.cells:
		if excluded.has(cell):
			return true
	return false

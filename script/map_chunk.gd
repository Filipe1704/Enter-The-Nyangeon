class_name MapChunk
extends RefCounted

var size: Vector2i = Vector2i.ONE
var coords: Vector2i
var cells: Array[Vector2i] = []
var world_center: Vector2 = Vector2.ZERO
var walkable_ratio: float = 0.0
var spawnable_cell_count: int = 0
var portal_cell_count: int = 0

func _init(p_coords: Vector2i = Vector2i.ZERO, p_size: Vector2i = Vector2i.ONE) -> void:
	coords = p_coords
	size = p_size

func has_portal_spawn() -> bool:
	return portal_cell_count > 0

func has_spawnable_cells() -> bool:
	return spawnable_cell_count > 0

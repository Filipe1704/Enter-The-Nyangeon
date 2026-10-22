class_name FogField
extends Node2D

const CLOUD_SCENE: PackedScene = preload("res://scenes/effects/fog/fog_cloud.tscn")

@export var settings: FogSettings
@export var density: float = 1.0
@export var emitter_spacing: float = 80.0
@export var y_sort_parent: NodePath

var _clouds: Array[FogCloud] = []
var _cloud_parent_override: Node
var _color_override := Color.WHITE
var _has_color_override := false
var _fading_out := false

func emit_rect(rect: Rect2) -> void:
	clear()
	if settings == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var scaled := maxf(0.05, density)
	var spacing := maxf(4.0, emitter_spacing / sqrt(scaled))
	var columns := maxi(1, int(ceil(rect.size.x / spacing)))
	var rows := maxi(1, int(ceil(rect.size.y / spacing)))
	var size := Vector2(spacing, spacing)
	for row in rows:
		for column in columns:
			var point := rect.position + Vector2(
				(float(column) + 0.5) * spacing,
				(float(row) + 0.5) * spacing
			)
			var edge_dist := minf(
				minf(point.x - rect.position.x, rect.end.x - point.x),
				minf(point.y - rect.position.y, rect.end.y - point.y)
			)
			var edge_fade := clampf(edge_dist / 48.0, 0.25, 1.0)
			_spawn_cloud(point, size, 1.0, edge_fade)
	start()

func emit_cells(cells: Array[Vector2i], cell_world: Callable) -> void:
	clear()
	for cell in cells:
		var point = cell_world.call(cell)
		if point is Vector2:
			_spawn_cloud(point, Vector2(emitter_spacing, emitter_spacing), maxf(0.05, density))
	start()

func emit_points(points: Array[Vector2]) -> void:
	clear()
	var size := Vector2(emitter_spacing, emitter_spacing)
	for point in points:
		_spawn_cloud(point, size, maxf(0.05, density))
	start()

func start() -> void:
	for cloud in _clouds:
		if cloud != null and is_instance_valid(cloud):
			cloud.start()

func stop() -> void:
	for cloud in _clouds:
		if cloud != null and is_instance_valid(cloud):
			cloud.stop()

func clear() -> void:
	for cloud in _clouds:
		if cloud != null and is_instance_valid(cloud):
			cloud.queue_free()
	_clouds.clear()

func fade_out() -> void:
	if _fading_out:
		return
	_fading_out = true
	stop()
	var wait := 2.0
	if settings != null:
		wait = maxf(0.2, settings.dissipate_time)
	var timer := get_tree().create_timer(wait + 0.1)
	timer.timeout.connect(_on_fade_finished, CONNECT_ONE_SHOT)

func _on_fade_finished() -> void:
	clear()
	queue_free()

func set_color(color: Color) -> void:
	_color_override = color
	_has_color_override = true
	for cloud in _clouds:
		if cloud != null and is_instance_valid(cloud):
			cloud.set_color(color)

func set_density(value: float) -> void:
	density = maxf(0.05, value)

func set_cloud_parent(parent: Node) -> void:
	_cloud_parent_override = parent

func _spawn_cloud(point: Vector2, size: Vector2, amount_scale: float, alpha_scale: float = 1.0) -> void:
	if settings == null:
		return
	var cloud := CLOUD_SCENE.instantiate() as FogCloud
	if cloud == null:
		return
	var parent := _resolve_cloud_parent()
	parent.add_child(cloud)
	cloud.global_position = point
	cloud.configure(settings, Rect2(Vector2.ZERO, size), amount_scale, alpha_scale)
	if _has_color_override:
		cloud.set_color(_color_override)
	_clouds.append(cloud)

func _resolve_cloud_parent() -> Node:
	if _cloud_parent_override != null and is_instance_valid(_cloud_parent_override):
		return _cloud_parent_override
	if y_sort_parent != NodePath():
		var node := get_node_or_null(y_sort_parent)
		if node != null:
			return node
	return self

extends Node2D

@export var cover_ratio: float = 1.1
@export var fallback_diameter: float = 48.0
@export var base_visual_diameter: float = 172.8

var _target_body: Node

func _ready() -> void:
	set_process(false)

func fit_to_enemy(body: Node) -> void:
	if body == null or not is_instance_valid(body) or not (body is Node2D):
		_target_body = null
		set_process(false)
		return
	_target_body = body
	_refresh_fit()
	set_process(true)

func _process(_delta: float) -> void:
	if _target_body == null or not is_instance_valid(_target_body) or not (_target_body is Node2D):
		_target_body = null
		set_process(false)
		return
	_refresh_fit()

func _refresh_fit() -> void:
	var bounds := _hurt_box_bounds(_target_body)
	var diameter := maxf(maxf(bounds["size"].x, bounds["size"].y), fallback_diameter) * cover_ratio
	position = bounds["center"]
	scale = Vector2.ONE * (diameter / maxf(base_visual_diameter, 1.0))

func _hurt_box_bounds(body: Node) -> Dictionary:
	var shape_node: Node = body.get("hurt_box_shape_2d")
	if shape_node == null:
		shape_node = body.get_node_or_null("HurtBox/HurtBoxShape2D")
	if shape_node == null:
		shape_node = body.get("collision_shape_2d")
	if shape_node == null or not (shape_node is Node2D):
		return {"size": Vector2(fallback_diameter, fallback_diameter), "center": Vector2.ZERO}
	var shape = shape_node.get("shape")
	if shape == null:
		return {"size": Vector2(fallback_diameter, fallback_diameter), "center": Vector2.ZERO}
	var size := Vector2.ZERO
	if shape is RectangleShape2D:
		size = (shape as RectangleShape2D).size
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		size = Vector2(radius * 2.0, radius * 2.0)
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		size = Vector2(capsule.radius * 2.0, capsule.height)
	if size == Vector2.ZERO:
		return {"size": Vector2(fallback_diameter, fallback_diameter), "center": Vector2.ZERO}
	var scale_factor := (shape_node as Node2D).global_transform.get_scale().abs()
	return {
		"size": size * scale_factor,
		"center": body.to_local((shape_node as Node2D).global_position),
	}

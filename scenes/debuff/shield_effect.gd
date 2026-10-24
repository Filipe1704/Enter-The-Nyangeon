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
	var bounds := HurtBoxMeasure.measure(_target_body, fallback_diameter)
	var diameter := maxf(maxf(bounds["size"].x, bounds["size"].y), fallback_diameter) * cover_ratio
	position = bounds["center"]
	scale = Vector2.ONE * (diameter / maxf(base_visual_diameter, 1.0))

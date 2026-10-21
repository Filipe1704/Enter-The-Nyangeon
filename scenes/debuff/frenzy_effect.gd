extends Node2D

const FALLBACK_DIAMETER := 36.0
const RING_COVER_RATIO := 1.7
const RING_MIN := 34.0
const RING_MAX := 110.0
const BAR_WIDTH := 44.0
const BAR_HEIGHT := 6.0
const BAR_GAP := 2.0

@export_range(0.25, 2.0, 0.05) var visual_scale: float = 0.5

@onready var _aura: ColorRect = $Aura
@onready var _embers: GPUParticles2D = $Embers
@onready var _burst: GPUParticles2D = $Burst
@onready var _bar: ColorRect = $BurnBar

var _target_body: Node
var _bar_material: ShaderMaterial
var _burning := false
var _aura_base_alpha := 1.0
var _flash_tween: Tween
var _bar_attached_to_overhead := false

func _ready() -> void:
	set_process(false)
	_bar_material = _bar.material as ShaderMaterial
	if _bar_material != null:
		_bar_material = _bar_material.duplicate() as ShaderMaterial
		_bar.material = _bar_material
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not _bar.resized.is_connected(_sync_bar_shader_size):
		_bar.resized.connect(_sync_bar_shader_size)
	_sync_bar_shader_size()
	_aura_base_alpha = _aura.modulate.a
	_bar.visible = false
	_bar.modulate = Color(1, 1, 1, 0)

func _exit_tree() -> void:
	if _bar != null and is_instance_valid(_bar):
		if _bar.get_parent() != self:
			if _target_body != null and is_instance_valid(_target_body) and _target_body.has_method("remove_overhead_item"):
				_target_body.remove_overhead_item(_bar)
			_bar.queue_free()
		_bar = null

func fit_to_enemy(body: Node) -> void:
	if body == null or not is_instance_valid(body) or not (body is Node2D):
		_target_body = null
		set_process(false)
		return
	_target_body = body
	_attach_bar(body)
	_refresh_fit()
	set_process(true)

func reset_marker() -> void:
	_burning = false
	_kill_flash_tween()
	_bar.visible = false
	_bar.modulate = Color(1, 1, 1, 0)
	_aura.modulate = Color(1, 1, 1, _aura_base_alpha)
	_embers.speed_scale = 1.0
	_embers.modulate = Color(1, 1, 1, 1)
	_burst.emitting = false

func begin_burn(_duration: float) -> void:
	_burning = true
	_kill_flash_tween()
	_bar.visible = true
	_bar.modulate = Color(1, 1, 1, 0)
	set_burn_progress(1.0)
	var tween := create_tween()
	tween.tween_property(_bar, "modulate:a", 1.0, 0.1)
	_aura.modulate = Color(1, 1, 1, 1)
	_embers.speed_scale = 1.6
	_burst.restart()

func set_burn_progress(value: float) -> void:
	if _bar_material == null:
		return
	_bar_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))

func flash_blocked() -> void:
	if not _burning:
		return
	_kill_flash_tween()
	_bar.modulate = Color(1.45, 1.25, 1.0, 1)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_bar, "modulate", Color(1, 1, 1, 1), 0.18)
	_burst.restart()

func finish_burn() -> void:
	_burning = false
	_kill_flash_tween()
	set_burn_progress(0.0)
	_bar.visible = false
	_bar.modulate = Color(1, 1, 1, 0)
	_aura.modulate = Color(1, 1, 1, _aura_base_alpha)
	_embers.speed_scale = 1.0

func _process(_delta: float) -> void:
	if _target_body == null or not is_instance_valid(_target_body) or not (_target_body is Node2D):
		_target_body = null
		set_process(false)
		return
	_refresh_fit()

func _refresh_fit() -> void:
	var bounds := _hurt_box_bounds(_target_body)
	var size: Vector2 = bounds["size"]
	var center: Vector2 = bounds["center"]
	position = center

	var shrink := clampf(visual_scale, 0.1, 2.0)
	var ring_diameter := clampf(maxf(size.x, size.y) * RING_COVER_RATIO, RING_MIN, RING_MAX) * shrink
	var ring_size := Vector2(ring_diameter, ring_diameter * 0.5)
	_aura.size = ring_size
	_aura.position = Vector2(-ring_size.x * 0.5, size.y * 0.5 - ring_size.y * 0.5)

	_embers.position = Vector2(0, size.y * 0.5 - 2.0)
	_embers.scale = Vector2.ONE * shrink

	if not _bar_attached_to_overhead:
		_bar.position = Vector2(-BAR_WIDTH * 0.5, -size.y * 0.5 - BAR_GAP - BAR_HEIGHT)
	_burst.position = Vector2(0, -size.y * 0.15)
	_burst.scale = Vector2.ONE * shrink

func _kill_flash_tween() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null

func _attach_bar(body: Node) -> void:
	if _bar == null or not is_instance_valid(_bar):
		return
	if body.has_method("add_overhead_item") and body.add_overhead_item(_bar):
		_bar_attached_to_overhead = true
	else:
		_bar_attached_to_overhead = false
		if _bar.get_parent() != self:
			_bar.reparent(self)
		_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_sync_bar_shader_size()

func _sync_bar_shader_size() -> void:
	if _bar_material == null or _bar == null:
		return
	var bar_size := _bar.size
	if bar_size.x <= 0.0 or bar_size.y <= 0.0:
		bar_size = _bar.custom_minimum_size
	_bar_material.set_shader_parameter("bar_size_px", bar_size)

func _hurt_box_bounds(body: Node) -> Dictionary:
	var shape_node: Node = body.get("hurt_box_shape_2d")
	if shape_node == null:
		shape_node = body.get_node_or_null("HurtBox/HurtBoxShape2D")
	if shape_node == null:
		shape_node = body.get("collision_shape_2d")
	if shape_node == null or not is_instance_valid(shape_node) or not (shape_node is Node2D):
		return {"size": Vector2(FALLBACK_DIAMETER, FALLBACK_DIAMETER), "center": Vector2.ZERO}
	var shape = shape_node.get("shape")
	if shape == null:
		return {"size": Vector2(FALLBACK_DIAMETER, FALLBACK_DIAMETER), "center": Vector2.ZERO}
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
		return {"size": Vector2(FALLBACK_DIAMETER, FALLBACK_DIAMETER), "center": Vector2.ZERO}
	var scale_factor := (shape_node as Node2D).global_transform.get_scale().abs()
	return {
		"size": size * scale_factor,
		"center": body.to_local((shape_node as Node2D).global_position),
	}

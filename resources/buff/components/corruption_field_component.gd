extends BuffComponent

const FIELD_POOL_ID: String = "corruption_field"
const FIELD_SCENE: PackedScene = preload("res://scenes/debuff/corruption_field.tscn")
const CORRUPTION_TINT: Color = Color(0.426, 0.178, 1.0, 1.0)
const CORRUPTION_BLEND: float = 0.3

var stats: EnemyStats
var carrier_buff: Buff = null
var carrier_value: Array = [1, 1.0, 99999.0]
var _spawned: bool = false
var _dead_cb: Callable = Callable()
var _visual_target: CanvasItem = null
var _original_modulate: Color = Color.WHITE
var _tint_material: ShaderMaterial = null
var _original_material: Material = null
var _original_tint: Color = Color.WHITE
var _original_amount: float = 0.0

func activate(_entry: Dictionary) -> void:
	_disconnect_dead()
	stats = body.get("stats") as EnemyStats if body != null else null
	carrier_buff = _entry.get("resource", null) as Buff
	carrier_value = [1, 1.0, maxf(1.0, float(_entry.get("erase_time", 999990)) / 10.0)]
	_spawned = false
	if stats == null or not is_instance_valid(stats):
		stats = null
		return
	_dead_cb = Callable(self, "_on_dead")
	if not stats.is_dead.is_connected(_dead_cb):
		stats.is_dead.connect(_dead_cb)
	if body != null and body.has_method("create_damage_data"):
		body.call("create_damage_data")
	_apply_tint()

func deactivate() -> void:
	_clear_tint()
	_disconnect_dead()
	stats = null
	carrier_buff = null
	_spawned = false

func _apply_tint() -> void:
	_clear_tint()
	if body == null or not is_instance_valid(body):
		return
	var target := body.get("sprite_2d") as CanvasItem
	if target == null or not is_instance_valid(target):
		return
	_visual_target = target
	_original_modulate = target.modulate
	target.modulate = _original_modulate.lerp(CORRUPTION_TINT, CORRUPTION_BLEND)
	var material: Material = target.material
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader != null and shader.resource_path.ends_with("sprite_outline.gdshader"):
			var shader_material := material as ShaderMaterial
			if not shader_material.resource_local_to_scene:
				_original_material = shader_material
				shader_material = shader_material.duplicate(true) as ShaderMaterial
				target.material = shader_material
			_tint_material = shader_material
			var old_tint = shader_material.get_shader_parameter("corruption_tint")
			var old_amount = shader_material.get_shader_parameter("corruption_amount")
			_original_tint = old_tint if old_tint is Color else Color.WHITE
			_original_amount = float(old_amount) if old_amount != null else 0.0
			shader_material.set_shader_parameter("corruption_tint", CORRUPTION_TINT)
			shader_material.set_shader_parameter("corruption_amount", CORRUPTION_BLEND)

func _clear_tint() -> void:
	if _visual_target != null and is_instance_valid(_visual_target):
		_visual_target.modulate = _original_modulate
		if _original_material != null:
			_visual_target.material = _original_material
		elif _tint_material != null and is_instance_valid(_tint_material):
			_tint_material.set_shader_parameter("corruption_tint", _original_tint)
			_tint_material.set_shader_parameter("corruption_amount", _original_amount)
	_visual_target = null
	_tint_material = null
	_original_material = null

func _disconnect_dead() -> void:
	if stats != null and is_instance_valid(stats) and _dead_cb.is_valid():
		if stats.is_dead.is_connected(_dead_cb):
			stats.is_dead.disconnect(_dead_cb)
	_dead_cb = Callable()

func _on_dead() -> void:
	if _spawned:
		return
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if not (body is Node2D):
		return
	_spawned = true
	_spawn_field((body as Node2D).global_position)

func _spawn_field(position: Vector2) -> void:
	var layer: Node = null
	var player_root: Node = get_tree().get_first_node_in_group("PlayerRoot")
	if player_root != null:
		layer = player_root.get_parent()
	if layer == null:
		layer = get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		return
	var field: Node = null
	var pooled: Node = PoolManager.get_pool(FIELD_POOL_ID)
	if pooled != null and is_instance_valid(pooled) and pooled.is_inside_tree():
		if int(pooled.get("is_idle")) == 1:
			field = pooled
	if field == null:
		field = FIELD_SCENE.instantiate()
		if field == null:
			return
		layer.add_child(field)
	var node := field as Node2D
	if node == null:
		return
	node.global_position = position
	field.set("carrier_buff", carrier_buff)
	field.set("carrier_value", carrier_value)
	if field.has_method("active_state"):
		field.call("active_state")

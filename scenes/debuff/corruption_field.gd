extends Area2D

const PLAYER_HURTBOX_LAYER: int = 2048
const ENEMY_HURTBOX_LAYER: int = 16384
const QUERY_MAX_RESULTS: int = 32
const INFECT_TICKS: int = 10

@export var pool_id: String = "corruption_field"
@export var self_life: int = 80
@export var corruption_interval: int = 4
@export var corruption_ratio: float = 0.01
@export var min_corruption: int = 1
@export var slow_buff: Buff
@export var slow_value: Array[float] = [1.0, 0.7, 0.5]

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

var is_idle: int = 1
var life_time: int = 0
var tick_count: int = 0
var source_id: String = ""
var affected: Dictionary = {}
var infected: Dictionary = {}
var carrier_buff: Buff = null
var carrier_value: Array = [1, 1.0, 99999]

func _ready() -> void:
	PoolManager.add_pool(pool_id, self)
	GameEvents.round_end.connect(round_clear)
	GameEvents.round_upgrade.connect(round_clear)
	idle_state()

func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	_clear_all_slow()
	life_time = 0
	tick_count = 0
	source_id = ""
	infected.clear()
	visible = false
	global_position = Vector2.ZERO
	_set_particles_emitting(false)
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	set_physics_process(false)

func active_state() -> void:
	reset_physics_interpolation()
	_clear_all_slow()
	is_idle = 0
	life_time = self_life
	tick_count = 0
	source_id = "corruption_field:%d" % get_instance_id()
	affected.clear()
	infected.clear()
	visible = true
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled", false)
	set_deferred("monitoring", true)
	_set_particles_emitting(true)
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	set_physics_process(true)

func time_count() -> void:
	if is_idle == 1:
		return
	tick_count += 1
	_refresh_players()
	if tick_count <= INFECT_TICKS:
		_infect_enemies()
	if corruption_interval > 0 and tick_count % corruption_interval == 0:
		_apply_corruption()
	life_time -= 1
	if life_time <= 0:
		idle_state()

func round_clear() -> void:
	_clear_all_slow()
	idle_state()
	PoolManager.erase_pool(pool_id)
	queue_free()

func _refresh_players() -> void:
	if slow_buff == null:
		_clear_all_slow()
		return
	var current := _query_players()
	for body in affected.keys():
		if body == null or not is_instance_valid(body) or not current.has(body):
			_remove_slow(body)
			affected.erase(body)
	for body in current.keys():
		BuffRouter.apply_buff(body, slow_buff, slow_value, source_id)
		affected[body] = true

func _query_players() -> Dictionary:
	var result: Dictionary = {}
	for hurt_box in _query_hurtboxes(PLAYER_HURTBOX_LAYER):
		if not hurt_box.is_player or not hurt_box.monitorable:
			continue
		var body: Node = hurt_box.body
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if body.get("is_downed") == true:
			continue
		var stats := body.get("stats") as Stats
		if stats == null or stats.hp <= 0:
			continue
		result[body] = true
	return result

func _query_hurtboxes(layer: int) -> Array:
	var result: Array = []
	if collision_shape_2d == null or collision_shape_2d.shape == null:
		return result
	var space := get_world_2d().direct_space_state
	if space == null:
		return result
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_shape_2d.shape
	params.transform = collision_shape_2d.global_transform
	params.collision_mask = layer
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in space.intersect_shape(params, QUERY_MAX_RESULTS):
		var hurt_box := hit.get("collider") as HurtBox
		if hurt_box != null:
			result.append(hurt_box)
	return result

func _infect_enemies() -> void:
	if carrier_buff == null:
		return
	for hurt_box in _query_hurtboxes(ENEMY_HURTBOX_LAYER):
		if hurt_box.is_player or not hurt_box.monitorable:
			continue
		var body: Node = hurt_box.body
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if infected.has(body):
			continue
		if body.get("is_idle") == 1:
			continue
		if Faction.of_entity(body) != Faction.ENEMY_SIDE:
			continue
		var stats := body.get("stats") as EnemyStats
		if stats == null or stats.hp <= 0:
			continue
		BuffRouter.apply_buff(body, carrier_buff, carrier_value, "corruption_field_infect:%d" % get_instance_id())
		infected[body] = true

func _apply_corruption() -> void:
	for body in affected.keys():
		if body == null or not is_instance_valid(body):
			continue
		var stats := body.get("stats") as Stats
		if stats == null or stats.hp <= 0:
			continue
		var amount := maxi(min_corruption, roundi(float(stats.max_hp) * corruption_ratio))
		stats.add_corruption(amount)

func _remove_slow(body: Node) -> void:
	if slow_buff == null or source_id == "":
		return
	if body == null or not is_instance_valid(body):
		return
	BuffRouter.remove_source(body, slow_buff, source_id)

func _clear_all_slow() -> void:
	for body in affected.keys():
		_remove_slow(body)
	affected.clear()

func _set_particles_emitting(value: bool) -> void:
	for child in get_children():
		var particles := child as GPUParticles2D
		if particles == null:
			continue
		particles.emitting = value
		if value:
			particles.restart()

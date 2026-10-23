extends Path2D

const COIN_SCENE: PackedScene = preload("res://scenes/item/coin.tscn")
const PATH_POOL_ID: String = "parabola_coins"
const COIN_POOL_ID: String = "coins"
const COIN_LAYER: int = 64

@onready var path: PathFollow2D = $PathFollow2D

@export var coin_num: int = 1
@export var min_drop_distance: float = 30.0
@export var max_drop_distance: float = 120.0
# -1 = 原 coin_box 的 0~PI 随机角度；>=0 时作为基准角度（可配合抖动）
@export var angle_override: float = -1.0
@export var clamp_to_walkable: bool = false
@export var map_clearance: float = 16.0
@export var ignore_coin_mult: bool = false
@export var ignore_auto_pick: bool = false
@export var play_drop_sound: bool = true
@export var arc_height: float = 300.0
@export var fall_duration: float = 3.0
@export var target_attempts: int = 8

var is_idle: int = 1
var body: Area2D = null
var _tween: Tween = null
var _drop_generation: int = 0
var _releasing: bool = false
var _body_layer: int = COIN_LAYER

func _ready() -> void:
	PoolManager.add_pool(PATH_POOL_ID, self)

func drop(center_pos: Vector2) -> void:
	if is_idle == 0:
		return
	is_idle = 0
	_releasing = false
	_drop_generation += 1
	var generation: int = _drop_generation
	visible = true
	body = _acquire_body()
	if body == null:
		is_idle = 1
		return
	body.coin = coin_num
	body.pick_up = false
	body.target = null
	body.can_pick = false
	body.ignore_coin_mult = ignore_coin_mult
	body.ignore_auto_pick = ignore_auto_pick
	_body_layer = body.collision_layer if body.collision_layer != 0 else COIN_LAYER
	# 金币出生点就是玩家位置，会立刻与 PickBox 重叠；惩罚金币在飞行期间
	# 先退出拾取层，否则 PickBox 会在出生帧把 pick_up 置真，落地后自动飞回。
	var suppress_pickbox: bool = body.ignore_auto_pick
	if suppress_pickbox:
		body.collision_layer = 0
	body.idled.connect(_on_body_idled, CONNECT_ONE_SHOT)
	body.active_state()
	if play_drop_sound:
		SoundManager.play_sfx("ButtonSounds")
	var end_pos := _pick_end_pos(center_pos)
	var ctrl_pos = Vector2(end_pos.x, center_pos.y - arc_height)

	curve = Curve2D.new()

	var point_count = 20
	for t in point_count:
		var point = _quadratic_bezier(center_pos, ctrl_pos, end_pos, t * 1.0/point_count)
		curve.add_point(point)

	path.progress_ratio = 0

	var tween = path.create_tween()
	_tween = tween
	tween.tween_property(path, "progress_ratio", 1, fall_duration).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	await tween.finished
	if generation != _drop_generation or is_idle == 1 or body == null:
		return
	body.can_pick = true
	if suppress_pickbox:
		body.pick_up = false
		body.target = null
		body.collision_layer = _body_layer
	_tween = null

func idle_state() -> void:
	if is_idle == 1 and body == null:
		return
	if _releasing:
		return
	_drop_generation += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if path != null:
		path.progress_ratio = 0
	visible = false
	if body == null:
		is_idle = 1
		_reset_drop_config()
		return
	if body.is_idle == 0:
		# body.idle_state() 会发 idled，由 _on_body_idled 回收。
		body.idle_state()
	else:
		_releasing = true
		_release_body()

func clear_uncollected() -> void:
	if is_idle == 1 and body == null:
		return
	idle_state()

func _acquire_body() -> Area2D:
	var follow := get_node_or_null("PathFollow2D")
	if follow == null:
		return null
	var coin = PoolManager.get_pool_idle(COIN_POOL_ID)
	if coin == null:
		coin = COIN_SCENE.instantiate()
		follow.add_child(coin)
	elif coin.get_parent() != follow:
		coin.reparent(follow, false)
	coin.position = Vector2.ZERO
	return coin as Area2D

func _on_body_idled() -> void:
	if _releasing:
		return
	_releasing = true
	_release_body()

func _release_body() -> void:
	var released := body
	body = null
	if released != null and is_instance_valid(released):
		released.can_pick = false
		released.collision_layer = _body_layer
		var tree := get_tree()
		var root = tree.get_first_node_in_group("CoinRoot") if tree != null else null
		if root != null:
			released.reparent(root, false)
			released.position = Vector2.ZERO
			PoolManager.add_pool(COIN_POOL_ID, released)
		else:
			released.queue_free()
	_releasing = false
	is_idle = 1
	_drop_generation += 1
	visible = false
	if path != null:
		path.progress_ratio = 0
	_reset_drop_config()

func _reset_drop_config() -> void:
	# 路径池会在 coin_box 与索尼克之间复用；恢复 coin_box 的默认配置，
	# 避免上一次索尼克掉落的 1.2s / ignore_auto_pick / clamp 泄漏到普通金币。
	coin_num = 1
	min_drop_distance = 30.0
	max_drop_distance = 120.0
	angle_override = -1.0
	clamp_to_walkable = false
	map_clearance = 16.0
	ignore_coin_mult = false
	ignore_auto_pick = false
	play_drop_sound = true
	arc_height = 300.0
	fall_duration = 3.0
	target_attempts = 8

func _pick_end_pos(center_pos: Vector2) -> Vector2:
	var min_dist := maxf(0.0, minf(min_drop_distance, max_drop_distance))
	var max_dist := maxf(min_dist, maxf(min_drop_distance, max_drop_distance))
	var candidate := center_pos + Vector2.from_angle(_drop_angle()) * randf_range(min_dist, max_dist)
	if not clamp_to_walkable:
		return candidate
	var fallback := candidate
	var attempts := maxi(1, target_attempts)
	for _i in attempts:
		var world_pos := to_global(candidate)
		var clamped := MapBounds.nearest_inside(world_pos, map_clearance)
		fallback = to_local(clamped)
		if clamped.distance_squared_to(world_pos) <= 0.01:
			return candidate
		candidate = center_pos + Vector2.from_angle(_drop_angle()) * randf_range(min_dist, max_dist)
	return fallback

func _drop_angle() -> float:
	if angle_override < 0.0:
		return randf_range(0.0, PI)
	return angle_override + randf_range(-0.2, 0.2)
	

func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float):
	var q0 = p0.lerp(p1, t)
	var q1 = p1.lerp(p2, t)
	var r = q0.lerp(q1, t)
	return r

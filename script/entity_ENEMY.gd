extends CharacterBody2D
class_name Enemy

const DEATH_ANIM_SCRIPT = preload("res://script/death_anim.gd")

signal is_hurt
@warning_ignore("unused_signal")
signal is_dead
@warning_ignore("unused_signal")
signal coin_done
signal is_knockback
signal convert_gauge_changed(gauge: int, threshold: int)
signal converted_changed(converted: bool)

@export var pool_id: String
@export var icon:String
@export var stats: EnemyStats
@export var sprite_2d: Node
@export var graphics: Node
@export var collision_shape_2d: CollisionShape2D
@export var enemy_buff_manager: Node
@export var line_color: Color = Color(2,2,2)
@export var body_part: Array[EnemyPart]

@onready var health_component = $HealthComponent
@onready var hurt_box_shape_2d = $HurtBox/HurtBoxShape2D
@onready var state_machine: Node = get_node_or_null("StateMachine")

var damage_data: DamageData

const coin:PackedScene = preload("res://scenes/item/coin.tscn")

const SOFT_COLLISION_FORCE := 160.0

var is_critical_hit:bool = false
var is_fire_hit:bool = false
var is_explosion_hit:bool = false
var is_poison_hit:bool = false

var ACCELERATION:float

var hurt_damage:int = 0
var hurt_knockback:int = 0
var hurt_direction:Vector2

var enemy_body: Array = []

var can_knockback: bool = true
var in_knockback: bool = false

var player: Node

# 玩家会在换角色时被销毁重建；敌人是池化实体，取用前统一重新解析（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

# 路线目标（path 敌人专用）。独立于 player 存储，任何重置 player 的逻辑都不会丢掉路线。
var route_target: Node = null

var is_idle: int = 1

var knockback_time: int = 0
var flash_time: int = 0

var direction: Vector2 = Vector2.ZERO

var frozen: bool = false

var faction: int = Faction.ENEMY_SIDE

var aggro_override: Node = null #嘲讽目标（人偶等），非空时优先攻击它

const CONVERTED_BUFF: Buff = preload("res://resources/buff/player_buff/converted_buff.tres")
const CONVERT_DAMAGE: PackedScene = preload("res://scenes/debuff/convert_damage.tscn")
const CONVERTED_BUFF_DURATION := 3.0 #策反buff持续时间（秒）
const CONVERT_BREAK_RATIO := 0.1 #破条真实伤害 = 10% max_hp
const CONVERT_TINT := Color(0.003, 13.636, 16.472) #策反描边色（亮蓝）
const CONVERT_OUTLINE_WIDTH := 1.0 #策反时强制描边宽度
const OVERHEAD_GAP := 2.0
const OVERHEAD_SEPARATION := 4.0
const OVERHEAD_FALLBACK_TOP := -16.0

enum ConvertResult { NONE, CONVERTED, BREAK }

var convert_gauge: int = 0 #策反进度

var _outline_base: Dictionary = {} #各描边材质的初始 width/color，策反结束后恢复用

var overhead_margin: MarginContainer
var overhead_stack: VBoxContainer
var _overhead_buff_box: Control
var _overhead_layout_queued := false
static var _texture_used_rect_cache: Dictionary = {}

func _ready():
	player = PlayerRef.resolve(self)
	enemy_body.clear()
	if not is_knockback.is_connected(body_in_knockback):
		is_knockback.connect(body_in_knockback)
	if not is_hurt.is_connected(_on_is_hurt):
		is_hurt.connect(_on_is_hurt)
	if not stats.is_dead.is_connected(_on_enemy_stats_is_dead):
		stats.is_dead.connect(_on_enemy_stats_is_dead)
	if enemy_buff_manager != null and not enemy_buff_manager.buff_expired.is_connected(_on_buff_expired):
		enemy_buff_manager.buff_expired.connect(_on_buff_expired)
	_setup_overhead_display()
	PoolManager.add_pool(pool_id, self)

func _exit_tree() -> void:
	PoolManager.unregister_active_enemy(self)

func idle_state():
	reset_physics_interpolation()
	is_idle = 1
	_target_cache = null
	_target_cache_frame = -1
	route_target = null
	PoolManager.unregister_active_enemy(self)
	frozen = false
	faction = Faction.ENEMY_SIDE
	convert_gauge = 0
	remove_from_group("Converted")
	_propagate_faction()
	_set_convert_visual(false)
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	enemy_body.clear()
	self.visible = false
	self.global_position = Vector2.ZERO
	# 延迟写入：idle_state 可能在命中/死亡结算（物理 query flush 期）被调用
	collision_shape_2d.set_deferred("disabled", true)
	hurt_box_shape_2d.set_deferred("disabled", true)
	enemy_buff_manager.clear_all_buff()
	if state_machine != null:
		state_machine.set_physics_process(false)
	set_physics_process(false)
	_interrupt_weapons()
	for part in body_part:
		if part != null and is_instance_valid(part) and part.has_method("idle_state"):
			part.idle_state()

func _interrupt_weapons() -> void:
	for n in find_children("*", "", true, false):
		if n.has_method("stop_firing"):
			n.stop_firing()
		elif n.has_method("stop_shoot"):
			n.stop_shoot()

func active_state():
	reset_physics_interpolation()
	is_idle = 0
	_target_cache = null
	_target_cache_frame = -1
	frozen = false
	_cache_outline_base()
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	stats.spawn_hp()
	
	create_damage_data()
	
	self.visible = true
	collision_shape_2d.set_deferred("disabled", false)
	hurt_box_shape_2d.set_deferred("disabled", false)
	if state_machine != null:
		state_machine.set_physics_process(true)
	set_physics_process(true)
	PoolManager.register_active_enemy(self)

func create_damage_data():
	var cfg := {
		"knockback": stats.Enemy_Knockback,
		"type": GameTags.MELEE_DAMAGE,
		"node": self,
	}
	if faction == Faction.PLAYER_SIDE:
		cfg["damage"] = DamageRouter.converted_damage(_ensure_player(), self)
		cfg["source"] = GameTags.CONVERTED
	else:
		cfg["damage"] = stats.Enemy_damage
		cfg["source"] = GameTags.ENEMY
	damage_data = DamageData.fill(damage_data, cfg)
	if faction != Faction.PLAYER_SIDE:
		var corruption: int = ChipCorruptionRules.attack_corruption(self)
		if corruption >= 1:
			damage_data.corruption_power = corruption

func move(delta: float, acceleration_local: float ,MAX_SPEED: float ) -> void:
	
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, acceleration_local * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, acceleration_local * delta)
		
		if direction.x > 0:
			graphics.scale.x = 1
		elif direction.x < 0:
			graphics.scale.x = -1
	
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

# 目标缓存：按物理帧节流，避免子类每帧重复选敌；null 也缓存，
# 防止「无目标」时每帧重扫。约 6 帧 ≈ 0.1s（60fps）。
var _target_cache: Node = null
var _target_cache_frame: int = -1
const TARGET_CACHE_FRAMES := 6

func get_target() -> Node:
	var f := Engine.get_physics_frames()
	if _target_cache_frame < 0 or (f - _target_cache_frame) >= TARGET_CACHE_FRAMES:
		_target_cache = _select_target()
		_target_cache_frame = f
	if _target_cache != null and not is_instance_valid(_target_cache):
		_target_cache = null
	return _target_cache

func _select_target() -> Node:
	if faction == Faction.PLAYER_SIDE:
		return get_nearest_enemy()
	if aggro_override != null and is_instance_valid(aggro_override):
		return aggro_override
	if route_target != null and is_instance_valid(route_target):
		return route_target
	# 联机 host：需把远端玩家镜像也纳入选敌（镜像在 "RemotePlayer" 组，非 "Player"）
	var nearest := get_nearest_player()
	if nearest != null:
		return nearest
	# 兜底 player 若已倒地（联机等待救援）则不再作为目标
	var p := _ensure_player()
	if p != null and not _is_valid_player_target(p):
		return null
	return p

# 最近存活玩家：单机/客机扫 "Player"；host 额外扫 "RemotePlayer"（远端镜像）。按物理帧缓存。
var _nearest_player_cache: Node = null
var _nearest_player_cache_frame: int = -1

func get_nearest_player() -> Node:
	var frame := Engine.get_physics_frames()
	if frame == _nearest_player_cache_frame and is_instance_valid(_nearest_player_cache):
		return _nearest_player_cache
	var is_net: bool = multiplayer.multiplayer_peer != null
	var include_mirrors: bool = is_net and multiplayer.is_server()
	var best: Node = null
	var best_d: float = INF
	for candidate in get_tree().get_nodes_in_group("Player"):
		if not _is_valid_player_target(candidate):
			continue
		var d: float = global_position.distance_squared_to((candidate as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = candidate
	if include_mirrors:
		for candidate in get_tree().get_nodes_in_group("RemotePlayer"):
			if not _is_valid_player_target(candidate):
				continue
			var d: float = global_position.distance_squared_to((candidate as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = candidate
	_nearest_player_cache_frame = frame
	_nearest_player_cache = best
	return best

func _is_valid_player_target(candidate) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if not (candidate is Node2D):
		return false
	if candidate.get("is_downed") == true:
		return false
	return true

# 策反单位无敌对目标时待机：不移动、不转向、不射击（子类据此短路）。
func is_standby() -> bool:
	return faction == Faction.PLAYER_SIDE and get_target() == null

func get_target_position() -> Vector2:
	var t := get_target()
	if t != null:
		return t.global_position
	var p := _ensure_player()
	if p != null:
		return p.global_position
	return global_position

# 贴脸接触（enemy_body）优先；无接触则用 Targeting 的按物理帧缓存活跃敌人列表，
# 不再 get_tree().get_nodes_in_group("Enemy") 全组扫描。
func get_nearest_enemy() -> Node:
	var best: Node = null
	var best_d: float = INF
	for e in enemy_body:
		if e == null or not is_instance_valid(e):
			continue
		if e.get("faction") != null and e.faction == Faction.PLAYER_SIDE:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		return best
	return Targeting.nearest_enemy(global_position)

func get_direction_to_player():
	var t := get_target()
	if t != null and global_position.distance_to(t.global_position) > 5:
		return (t.global_position - global_position).normalized()
	return Vector2.ZERO

func time_count():
	
	direction = get_direction_to_player()
	
	_convert_tick()
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			_apply_outline_state()
	
	if knockback_time > 0:
		knockback_time -= 1
		if knockback_time <= 0:
			body_end_knockback()

func apply_conversion_power(power: int) -> int:
	if power <= 0:
		return ConvertResult.NONE
	if is_in_group("EnemyPart"):
		return ConvertResult.NONE
	# 联机：客机转发 host 权威结算（本端镜像不本地累积/策反）
	if ExtensionHooks.intercept_named("enemy_conversion_interceptor", [self, power]):
		return ConvertResult.NONE
	if faction == Faction.PLAYER_SIDE:
		refresh_converted_buff()
		return ConvertResult.NONE
	var resist: int = clampi(stats.convert_resist, 0, 100)
	if resist >= 100:
		return ConvertResult.NONE
	var effective: int = max(1, int(round(power * DamageRouter.resist_factor(resist))))
	convert_gauge += effective
	convert_gauge_changed.emit(convert_gauge, stats.convert_threshold)
	PoolManager.spawn_fx("convert", CONVERT_DAMAGE, self)
	if convert_gauge >= stats.convert_threshold:
		convert_gauge = 0
		convert_gauge_changed.emit(0, stats.convert_threshold)
		if _can_convert():
			_on_convert()
			return ConvertResult.CONVERTED
		else:
			_on_convert_break()
			return ConvertResult.BREAK
	return ConvertResult.NONE

# 真实玩家引用：path 敌人的 player 被改写为路径节点，需单独解析
func _real_player() -> Node:
	var p: Node = PlayerData.player
	if p == null or p.get("stats") == null:
		p = get_tree().get_first_node_in_group("Player")
	if p == null or p.get("stats") == null:
		return null
	return p

func _can_convert() -> bool:
	if not stats.convertible:
		return false
	var p: Node = _real_player()
	if p == null:
		return false
	var converted_count := get_tree().get_nodes_in_group("Converted").size()
	return converted_count < p.stats.converted_cap

func _on_convert():
	_clear_all_buffs()
	faction = Faction.PLAYER_SIDE
	frozen = false
	add_to_group("Converted")
	_propagate_faction()
	create_damage_data()
	if enemy_buff_manager != null:
		var convert_duration: float = CONVERTED_BUFF_DURATION
		var p: Node = _real_player()
		if p != null:
			convert_duration = p.stats.convert_time
		enemy_buff_manager.apply_buff(CONVERTED_BUFF, [1, 1, convert_duration])
	_set_convert_visual(true)
	SoundManager.play_sfx_once("PowerUp1")
	converted_changed.emit(true)

func _on_revert():
	faction = Faction.ENEMY_SIDE
	remove_from_group("Converted")
	_propagate_faction()
	create_damage_data()
	_clear_all_buffs()
	_set_convert_visual(false)
	converted_changed.emit(false)

func _on_buff_expired(buff: Buff):
	if buff == null or buff.id != CONVERTED_BUFF.id:
		return
	if is_idle == 1 or faction != Faction.PLAYER_SIDE:
		return
	_on_revert()

func is_converted() -> bool:
	return faction == Faction.PLAYER_SIDE


# 联机镜像：按 host 快照应用策反状态（只做阵营/组/描边/gauge，无 buff/音效/伤害数据副作用；
# revert 由快照 converted=false 驱动）
func apply_network_conversion(gauge: int, converted: bool) -> void:
	convert_gauge = gauge
	convert_gauge_changed.emit(convert_gauge, stats.convert_threshold)
	var now_converted: bool = faction == Faction.PLAYER_SIDE
	if converted and not now_converted:
		faction = Faction.PLAYER_SIDE
		frozen = false
		add_to_group("Converted")
		_propagate_faction()
		_set_convert_visual(true)
		converted_changed.emit(true)
	elif (not converted) and now_converted:
		faction = Faction.ENEMY_SIDE
		remove_from_group("Converted")
		_propagate_faction()
		_set_convert_visual(false)
		converted_changed.emit(false)

func refresh_converted_buff():
	if enemy_buff_manager != null and enemy_buff_manager.has_method("refresh_buff"):
		enemy_buff_manager.refresh_buff(CONVERTED_BUFF.id)

func _clear_all_buffs():
	_clear_buffs_on(enemy_buff_manager)
	for part in body_part:
		if part == null or not is_instance_valid(part):
			continue
		_clear_buffs_on(part.get("enemy_buff_manager"))
		_clear_buffs_on(part.find_child("EnemyBuffManager", true, false))

func _clear_buffs_on(manager: Node):
	if manager != null and manager.has_method("clear_all_buff"):
		manager.clear_all_buff()

func _set_convert_visual(_active: bool):
	_apply_outline_state()

# 参与描边状态管理的材质（多材质敌人可覆写，如精英自动机的头部）
func _outline_materials() -> Array:
	return [sprite_2d]

# 记录各描边材质的初始宽度/颜色，供策反结束后恢复
func _cache_outline_base():
	for sp in _outline_materials():
		if sp == null or not is_instance_valid(sp):
			continue
		var mat = sp.get("material")
		if mat is ShaderMaterial and not _outline_base.has(mat):
			_outline_base[mat] = {
				"width": mat.get_shader_parameter("outline_width"),
				"color": mat.get_shader_parameter("outline_color"),
			}

# 统一按状态写入描边：策反时蓝色描边，否则恢复初始态
func _apply_outline_state():
	for sp in _outline_materials():
		if sp == null or not is_instance_valid(sp):
			continue
		var mat = sp.get("material")
		if not (mat is ShaderMaterial):
			continue
		var base: Dictionary = _outline_base.get(mat, {"width": 0.0, "color": line_color})
		if is_converted():
			mat.set_shader_parameter("outline_width", CONVERT_OUTLINE_WIDTH)
			mat.set_shader_parameter("outline_color", CONVERT_TINT)
			mat.set_shader_parameter("flash_opacity", 0.0)
		else:
			mat.set_shader_parameter("outline_width", base["width"])
			mat.set_shader_parameter("outline_color", base["color"])
			mat.set_shader_parameter("flash_opacity", 0.0)

func _propagate_faction():
	for part in body_part:
		if part != null and is_instance_valid(part):
			part.faction = faction

func _on_convert_break():
	convert_break_take_damage()
	for part in body_part:
		if part != null and is_instance_valid(part):
			part.convert_break_take_damage()

func convert_break_take_damage():
	health_component.take_damage(DamageData.make({
		"damage": max(1, int(stats.max_hp * CONVERT_BREAK_RATIO)),
		"flags": [GameTags.TRUE_DAMAGE],
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.CONVERTED,
		"node": self,
	}))

func _convert_tick():
	if has_meta("network_remote_enemy"):
		return
	if faction == Faction.PLAYER_SIDE:
		return
	if convert_gauge > 0:
		convert_gauge = max(0, convert_gauge - stats.convert_decay)
		convert_gauge_changed.emit(convert_gauge, stats.convert_threshold)

func body_in_knockback():
	in_knockback = true
	knockback_time = 5

func body_end_knockback():
	in_knockback = false

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	sprite_2d.material.set_shader_parameter("outline_color", Color(2,2,2))
	flash_time = 1

func apply_knockback(knockback_velocity: Vector2):
	if knockback_velocity != Vector2.ZERO:
		body_in_knockback()
		self.velocity = knockback_velocity

func _on_damage():
	pass

func _coin_drops():
	if stats.Enemy_coin > 0:
		CoinManager.drop_coin(self.global_position, stats.Enemy_coin, stats.coin_pick)

# 回合结束清场时：被策反单位计为一次击杀并全额结算金币，返回本次结算金币值
func settle_converted_clear() -> int:
	if not is_converted():
		return 0
	GameEvents.emit_enemy_dead_score(stats.score)
	var p := _ensure_player()
	if p == null or p.get("stats") == null or stats.Enemy_coin <= 0:
		return 0
	var coin_value: int = int(ceil(stats.Enemy_coin * p.stats.coin_mult))
	p.stats.coin += coin_value
	GameEvents.emit_player_pick_up_coin(global_position)
	GameEvents.emit_player_coins_get(coin_value)
	return coin_value

func on_dead():
	GameEvents.emit_enemy_dead_position(self.global_position)
	idle_state.call_deferred()

# 回合清场：复用死亡粒子，但走纯视觉路径，不触发金币/分数/死亡位置/音效。
func play_clear_death() -> void:
	if has_meta("clear_death_played"):
		return
	if stats != null and stats.hp <= 0:
		return
	set_meta("clear_death_played", true)
	var death_anim := get_node_or_null("DeathAnim")
	if death_anim != null and death_anim.has_method("on_death_anim"):
		death_anim.on_death_anim(false)
		return
	DEATH_ANIM_SCRIPT.spawn_for_enemy(self, false)

func _on_is_hurt():
	pass

func _on_enemy_stats_is_dead():
	_coin_drops.call_deferred()
	on_dead.call_deferred()

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and not enemy_body.has(body) and body != self and not body.is_in_group("EnemyPart"):
		enemy_body.append(body)
	if body.is_in_group("Enemy") and body != self and not body.is_in_group("EnemyPart") and (not is_in_group("BOSS") or body.is_in_group("BOSS")):
		var total = stats.weigth + body.stats.weigth
		if total > 0:
			var dir = (global_position - body.global_position).normalized()
			velocity += (body.stats.weigth / total) * dir * SOFT_COLLISION_FORCE * 0.5

func _on_area_2d_body_exited(body):
	if is_idle == 1:
		return
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		if in_knockback == false and not (body.is_in_group("BOSS") and not is_in_group("BOSS")):
			body.velocity = velocity.limit_length(body.stats.MAX_SPEED)

func apply_soft_collision():
	if enemy_body.is_empty():
		return
	for i in enemy_body:
		if i == null or not is_instance_valid(i):
			continue
		if i.is_in_group("BOSS") and not is_in_group("BOSS"):
			continue
		var total = stats.weigth + i.stats.weigth
		if total <= 0:
			continue
		var dir = i.global_position - global_position
		var dist = dir.length()
		if dist <= 0:
			continue
		i.velocity += (stats.weigth / total) * (dir / dist) * SOFT_COLLISION_FORCE / max(0.5, dist)

func _setup_overhead_display() -> void:
	overhead_margin = get_node_or_null("MarginContainer") as MarginContainer
	if overhead_margin == null:
		return
	var buff_box := overhead_margin.find_child("BuffBox", true, false) as Control
	if buff_box == null:
		return
	overhead_stack = overhead_margin.get_node_or_null("OverheadStack") as VBoxContainer
	if overhead_stack == null:
		overhead_stack = VBoxContainer.new()
		overhead_stack.name = "OverheadStack"
		overhead_margin.add_child(overhead_stack)
	overhead_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overhead_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	overhead_stack.add_theme_constant_override("separation", int(OVERHEAD_SEPARATION))
	if buff_box.get_parent() != overhead_stack:
		buff_box.reparent(overhead_stack)
	_overhead_buff_box = buff_box
	overhead_stack.move_child(buff_box, overhead_stack.get_child_count() - 1)
	overhead_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not overhead_stack.minimum_size_changed.is_connected(_queue_overhead_layout):
		overhead_stack.minimum_size_changed.connect(_queue_overhead_layout)
	if not overhead_stack.resized.is_connected(_queue_overhead_layout):
		overhead_stack.resized.connect(_queue_overhead_layout)
	var sprite := sprite_2d
	if sprite != null and is_instance_valid(sprite):
		if sprite.has_signal("animation_changed") and not sprite.animation_changed.is_connected(_queue_overhead_layout):
			sprite.animation_changed.connect(_queue_overhead_layout)
		if sprite.has_signal("frame_changed") and not sprite.frame_changed.is_connected(_queue_overhead_layout):
			sprite.frame_changed.connect(_queue_overhead_layout)
	_queue_overhead_layout()

func add_overhead_item(item: Control) -> bool:
	if overhead_stack == null or not is_instance_valid(overhead_stack) or item == null or not is_instance_valid(item):
		return false
	if item.get_parent() != overhead_stack:
		item.reparent(overhead_stack)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var buff_index := overhead_stack.get_children().find(_overhead_buff_box)
	if buff_index >= 0:
		overhead_stack.move_child(item, buff_index)
	_queue_overhead_layout()
	return true

func remove_overhead_item(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return
	if overhead_stack != null and is_instance_valid(overhead_stack) and item.get_parent() == overhead_stack:
		overhead_stack.remove_child(item)
	_queue_overhead_layout()

func _queue_overhead_layout() -> void:
	if _overhead_layout_queued:
		return
	_overhead_layout_queued = true
	_refresh_overhead_layout.call_deferred()

func _refresh_overhead_layout() -> void:
	_overhead_layout_queued = false
	if overhead_margin == null or overhead_stack == null:
		return
	if not is_instance_valid(overhead_margin) or not is_instance_valid(overhead_stack):
		return
	var content_size := overhead_stack.get_combined_minimum_size()
	overhead_margin.size = content_size
	var scale_x := absf(overhead_margin.scale.x)
	var scale_y := absf(overhead_margin.scale.y)
	if scale_x <= 0.0:
		scale_x = 0.5
	if scale_y <= 0.0:
		scale_y = 0.5
	var head_y := get_visible_head_local_y()
	overhead_margin.position = Vector2(
		-content_size.x * scale_x * 0.5,
		head_y - OVERHEAD_GAP - content_size.y * scale_y
	)

func get_visible_head_local_y() -> float:
	var fallback := _hurt_box_top_local()
	var sprite := sprite_2d as Node2D
	if sprite == null or not is_instance_valid(sprite) or not sprite.visible:
		return fallback
	var frames = sprite.get("sprite_frames")
	if frames is SpriteFrames:
		var animation: StringName = sprite.get("animation")
		var frame_count := (frames as SpriteFrames).get_frame_count(animation)
		var min_top := INF
		for i in frame_count:
			var texture: Texture2D = (frames as SpriteFrames).get_frame_texture(animation, i)
			min_top = minf(min_top, _frame_visible_top_global(sprite, texture))
		if min_top < INF:
			return to_local(Vector2(global_position.x, min_top)).y
	else:
		var texture = sprite.get("texture")
		if texture is Texture2D:
			var top_global := _frame_visible_top_global(sprite, texture)
			if top_global < INF:
				return to_local(Vector2(global_position.x, top_global)).y
	return fallback

func _frame_visible_top_global(sprite: Node2D, texture: Texture2D) -> float:
	var rect := _texture_visible_rect_local(sprite, texture)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return INF
	var xf := sprite.global_transform
	var p0 := xf * rect.position
	var p1 := xf * (rect.position + Vector2(rect.size.x, 0.0))
	var p2 := xf * (rect.position + Vector2(0.0, rect.size.y))
	var p3 := xf * rect.end
	return minf(minf(p0.y, p1.y), minf(p2.y, p3.y))

func _texture_visible_rect_local(sprite: Node2D, texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var used := _texture_used_rect(texture)
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()
	var pos := -texture.get_size() * 0.5
	var centered = sprite.get("centered")
	if centered is bool and not centered:
		pos = Vector2.ZERO
	var offset = sprite.get("offset")
	if offset is Vector2:
		pos += offset
	return Rect2(pos + Vector2(used.position), Vector2(used.size))

static func _texture_used_rect(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var key := texture.get_instance_id()
	if _texture_used_rect_cache.has(key):
		return _texture_used_rect_cache[key]
	var used := Rect2i()
	var image := texture.get_image()
	if image != null:
		var texture_size := Vector2i(texture.get_size())
		if image.get_width() != texture_size.x or image.get_height() != texture_size.y:
			if texture is AtlasTexture:
				var atlas := (texture as AtlasTexture).atlas
				if atlas != null:
					var region := Rect2i((texture as AtlasTexture).region)
					var image_rect := Rect2i(Vector2i.ZERO, image.get_size())
					region = region.intersection(image_rect)
					if region.size.x > 0 and region.size.y > 0:
						image = image.get_region(region)
		used = image.get_used_rect()
	_texture_used_rect_cache[key] = used
	return used

func _hurt_box_top_local() -> float:
	var shape_node: Node = hurt_box_shape_2d
	if shape_node == null:
		shape_node = collision_shape_2d
	if shape_node == null or not is_instance_valid(shape_node) or not (shape_node is Node2D):
		return OVERHEAD_FALLBACK_TOP
	var shape = shape_node.get("shape")
	if shape == null:
		return OVERHEAD_FALLBACK_TOP
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
		return OVERHEAD_FALLBACK_TOP
	var scale_factor := (shape_node as Node2D).global_transform.get_scale().abs()
	size *= scale_factor
	var center := to_local((shape_node as Node2D).global_position)
	return center.y - size.y * 0.5

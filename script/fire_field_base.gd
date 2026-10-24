class_name FireFieldBase
extends Node2D

## 火场公共生命周期基类：debuff 侧 fire_field 与道具侧 renge_fire_field 共用。
## 伤害公式、就绪/到期行为、伤害来源标签等差异由子类钩子决定，钩子语义见各注释。

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var hit_box = $Area2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var value: Array
var damage_cd: int = 2
var time_length: int = 0
var body_group: Array[Node] = []
var is_idle: int = 1
var is_ready: bool = false

func _ready() -> void:
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_exited)
	_on_field_ready()

func idle_state():
	reset_physics_interpolation()
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	if not body_group.is_empty():
		body_group.clear()
	gpu_particles_2d.emitting = false
	self.visible = false
	self.global_position = Vector2.ZERO
	hit_box.set_deferred("monitoring", false)

func active_state():
	reset_physics_interpolation()

	if is_ready == false:
		return

	is_idle = 0
	value = [buff_layer, buff_value, buff_erase_timer]
	damage_cd = 2
	time_length = _field_lifetime()
	if not body_group.is_empty():
		body_group.clear()
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	self.visible = true
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()
	hit_box.set_deferred("monitoring", true)
	_on_field_activated()
	apply_fire_damage_data()

func time_count():
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_damage_data()
			damage_cd = 2

	if time_length > 0:
		time_length -= 1
		if time_length <= 0:
			_on_field_expired()

func apply_fire_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"knockback": 0,
		"type": GameTags.FIRE_DAMAGE,
		"source": _damage_source(),
		"node": self,
	})

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and not body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_hit_box_exited(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and body_group.has(hurtbox):
		body_group.remove_at(body_group.find(hurtbox))

## 场景就绪（_ready）时的行为：默认置就绪并进入休眠，等待外部 active_state()。
func _on_field_ready() -> void:
	is_ready = true
	idle_state()

## 激活一次的持续 tick 数。
func _field_lifetime() -> int:
	return 0

## 每次激活时的额外复位（默认无）。
func _on_field_activated() -> void:
	pass

## 计时到期时的收尾（默认直接休眠）。
func _on_field_expired() -> void:
	idle_state()

## DamageData 的 source 标签（如 GameTags.PS_DAMAGE / GameTags.EQUIP）。
func _damage_source() -> String:
	return GameTags.PS_DAMAGE

## 命中结算（伤害公式各异，由子类实现）。
func add_damage_data() -> void:
	pass

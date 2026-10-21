extends Node2D

const SMOKE_ANIM_FALLBACK_SEC: float = 0.25

@export var pool_id: String = "bullet_smoke_2"

@onready var animation_player = $AnimationPlayer

var is_idle: int = 0
var _anim_gen: int = 0

func _ready():
	PoolManager.add_pool(pool_id,self)

func idle_state():
	_anim_gen += 1
	reset_physics_interpolation()
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	smoke_reset()

func active_state():
	reset_physics_interpolation()
	is_idle = 0
	self.visible = true

func smoke_reset():
	animation_player.play("RESET")

func smoke_anim():
	if not PoolManager.fx_allowed(&"bullet_smoke"):
		idle_state()
		return
	active_state()
	_anim_gen += 1
	var gen := _anim_gen
	animation_player.play("new_animation")
	_schedule_idle(gen)

func _schedule_idle(gen: int) -> void:
	if not is_inside_tree():
		return
	var wr: WeakRef = weakref(self)
	get_tree().create_timer(SMOKE_ANIM_FALLBACK_SEC).timeout.connect(func():
		var node = wr.get_ref()
		if node != null and is_instance_valid(node):
			node.call("_fallback_idle", gen)
	)

func _fallback_idle(gen: int) -> void:
	if gen != _anim_gen or is_idle == 1:
		return
	idle_state()

extends BuffComponent

const DECAY_PER_SHOT := 0.02
const DECAY_CAP := 0.20
const RESET_TIME := 1.0

var _gun: Node
var _active: bool = false
var _bind_retried: bool = false

func activate(_entry: Dictionary) -> void:
	_active = true
	_bind_retried = false
	_bind_gun()

func deactivate() -> void:
	_active = false
	if _gun == null or not is_instance_valid(_gun):
		_gun = null
		_bind_retried = false
		return
	_gun.sustained_fire_damage_decay_per_shot = 0.0
	_gun.sustained_fire_damage_decay_cap = 0.0
	_gun.sustained_fire_decay_reset_time = 1.0
	_gun.reset_sustained_fire()
	_gun = null
	_bind_retried = false

func _bind_gun() -> void:
	if not _active or body == null:
		return
	_gun = body.get("gun")
	if _gun == null:
		if _bind_retried:
			return
		_bind_retried = true
		call_deferred("_bind_gun")
		return
	_gun.sustained_fire_damage_decay_per_shot = DECAY_PER_SHOT
	_gun.sustained_fire_damage_decay_cap = DECAY_CAP
	_gun.sustained_fire_decay_reset_time = RESET_TIME
	_gun.reset_sustained_fire()
	_bind_retried = false

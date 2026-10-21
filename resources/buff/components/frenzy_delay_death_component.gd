extends BuffComponent

const _DEFAULT_EFFECT_SCENE := preload("res://scenes/debuff/frenzy_effect.tscn")

signal burn_started(duration: float)
signal burn_finished

@export var death_delay: float = 4.0
@export var effect_scene: PackedScene = _DEFAULT_EFFECT_SCENE

var stats: EnemyStats
var health: HealthComponent
var effect: Node2D
var _pending: bool = false
var _network_burn_left: float = 0.0
var _fatal_snapshot: DamageData
var _timer: Timer
var _guard := Callable()

func activate(_entry: Dictionary) -> void:
	stats = body.get("stats") if body != null else null
	health = body.get("health_component") if body != null else null
	if stats == null or health == null:
		return
	if _guard.is_valid():
		health.remove_fatal_damage_guard(_guard)
	_guard = Callable(self, "_on_fatal_damage")
	health.add_fatal_damage_guard(_guard)
	_ensure_timer()
	_pending = false
	_fatal_snapshot = null
	if _timer != null:
		_timer.stop()
	set_process(false)
	_ensure_effect()

func refresh(_entry: Dictionary) -> void:
	pass

func deactivate() -> void:
	set_process(false)
	_network_burn_left = 0.0
	burn_finished.emit()
	if health != null and is_instance_valid(health) and _guard.is_valid():
		health.remove_fatal_damage_guard(_guard)
	_guard = Callable()
	if _timer != null:
		_timer.stop()
	_pending = false
	_fatal_snapshot = null
	_free_effect()
	stats = null
	health = null

func _ensure_timer() -> void:
	if _timer != null and is_instance_valid(_timer):
		return
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = maxf(0.01, death_delay)
	_timer.timeout.connect(_on_delay_timeout)
	add_child(_timer)

func _on_fatal_damage(final_damage: int, damage_data) -> int:
	if stats == null or not is_instance_valid(stats) or stats.hp <= 0:
		return final_damage
	if final_damage < stats.hp:
		return final_damage
	var data := damage_data as DamageData
	if data != null and data.flags.has(GameTags.EXECUTE_DAMAGE):
		return final_damage
	if _pending:
		if effect != null and is_instance_valid(effect) and effect.has_method("flash_blocked"):
			effect.flash_blocked()
		return 0
	_pending = true
	_fatal_snapshot = _snapshot(data)
	_ensure_timer()
	_timer.wait_time = maxf(0.01, death_delay)
	_timer.start()
	if effect != null and is_instance_valid(effect) and effect.has_method("begin_burn"):
		effect.begin_burn(death_delay)
	set_process(true)
	burn_started.emit(death_delay)
	return maxi(0, stats.hp - 1)

func network_begin_burn(duration: float) -> void:
	if effect == null or not is_instance_valid(effect):
		_ensure_effect()
	_network_burn_left = maxf(0.01, duration)
	if effect != null and is_instance_valid(effect) and effect.has_method("begin_burn"):
		effect.begin_burn(_network_burn_left)
	set_process(true)

func network_finish_burn() -> void:
	_network_burn_left = 0.0
	if effect != null and is_instance_valid(effect) and effect.has_method("finish_burn"):
		effect.finish_burn()
	set_process(false)

func _process(delta: float) -> void:
	if _network_burn_left > 0.0:
		_network_burn_left = maxf(0.0, _network_burn_left - delta)
		if effect != null and is_instance_valid(effect) and effect.has_method("set_burn_progress"):
			effect.set_burn_progress(_network_burn_left / maxf(0.01, death_delay))
		if _network_burn_left <= 0.0:
			network_finish_burn()
		return
	if not _pending or _timer == null or not is_instance_valid(_timer):
		return
	if effect == null or not is_instance_valid(effect):
		return
	if not effect.has_method("set_burn_progress"):
		return
	var ratio := clampf(_timer.time_left / maxf(0.01, _timer.wait_time), 0.0, 1.0)
	effect.set_burn_progress(ratio)

func _ensure_effect() -> void:
	_free_effect()
	if effect_scene == null or body == null or not is_instance_valid(body) or not (body is Node2D):
		return
	effect = effect_scene.instantiate() as Node2D
	if effect == null:
		return
	body.add_child(effect)
	if effect.has_method("fit_to_enemy"):
		effect.fit_to_enemy(body)

func _free_effect() -> void:
	if effect == null:
		return
	if is_instance_valid(effect):
		effect.queue_free()
	effect = null

func _snapshot(damage_data: DamageData) -> DamageData:
	if damage_data == null:
		return null
	var snap := damage_data.duplicate() as DamageData
	if snap == null:
		return null
	snap.damage_modifier.clear()
	snap.on_damage_dealt.clear()
	snap.knockback_force = 0
	snap.knockback_direction = Vector2.ZERO
	return snap

func _on_delay_timeout() -> void:
	if not _pending:
		return
	_pending = false
	_network_burn_left = 0.0
	set_process(false)
	burn_finished.emit()
	if effect != null and is_instance_valid(effect) and effect.has_method("finish_burn"):
		effect.finish_burn()
	if stats == null or not is_instance_valid(stats) or stats.hp <= 0:
		_fatal_snapshot = null
		return
	if health == null or not is_instance_valid(health):
		stats.hp = 0
		return
	if _guard.is_valid():
		health.remove_fatal_damage_guard(_guard)
	var snap := _fatal_snapshot
	_fatal_snapshot = null
	var dead_damage: int = maxi(1, int(stats.hp))
	if snap != null:
		snap.base_damage = dead_damage
		health.take_damage(snap, true, false, dead_damage)
	else:
		stats.hp = 0
	if stats != null and is_instance_valid(stats) and stats.hp > 0:
		stats.hp = 0

extends BuffComponent

const FULL_HP_REDUCTION := 0.8
const REDUCTION_END_RATIO := 0.5
const UPDATE_EPSILON := 0.005
const BREAK_EPSILON := 0.0001
const ARMOR_BAR_SCENE: PackedScene = preload("res://ui/enemy_armor_bar.tscn")
const ARMOR_BREAK_SCENE: PackedScene = preload("res://scenes/debuff/armor_break.tscn")
const ARMOR_BREAK_SFX := "ArmorBreak"

var stats: EnemyStats
var health: HealthComponent
var _factor: float = 1.0
var _active: bool = false
var _bar: Control

func activate(_entry: Dictionary) -> void:
	if _active:
		if _bar == null or not is_instance_valid(_bar):
			_attach_bar()
		_refresh(true)
		return
	stats = body.get("stats") if body != null else null
	if stats == null or not is_instance_valid(stats):
		stats = null
		return
	health = body.get("health_component") if body != null else null
	if not stats.hp_changed.is_connected(_on_hp_changed):
		stats.hp_changed.connect(_on_hp_changed)
	if health != null and not health.damage_taken.is_connected(_on_damage_taken):
		health.damage_taken.connect(_on_damage_taken)
	_active = true
	_factor = 1.0
	_attach_bar()
	_refresh(true)
	call_deferred("_refresh", true)

func refresh(_entry: Dictionary) -> void:
	_refresh()

func deactivate() -> void:
	_active = false
	if stats != null and is_instance_valid(stats):
		if stats.hp_changed.is_connected(_on_hp_changed):
			stats.hp_changed.disconnect(_on_hp_changed)
		_apply_factor(1.0, false)
	if health != null and is_instance_valid(health):
		if health.damage_taken.is_connected(_on_damage_taken):
			health.damage_taken.disconnect(_on_damage_taken)
	stats = null
	health = null
	_factor = 1.0
	_detach_bar()

func _exit_tree() -> void:
	_detach_bar()

func _on_hp_changed() -> void:
	_refresh()

func _on_damage_taken(_actual_damage: int, _damage_data: DamageData) -> void:
	_refresh()

func _refresh(force: bool = false) -> void:
	if not _active or stats == null or not is_instance_valid(stats):
		return
	var target := _target_factor()
	var crossed := _is_broken(target) != _is_broken(_factor)
	if not force and not crossed and absf(target - _factor) < UPDATE_EPSILON:
		return
	_apply_factor(target)

func _target_factor() -> float:
	var max_hp := maxf(1.0, float(stats.max_hp))
	var ratio := clampf(float(stats.hp) / max_hp, 0.0, 1.0)
	var reduction := FULL_HP_REDUCTION * clampf(
		(ratio - REDUCTION_END_RATIO) / (1.0 - REDUCTION_END_RATIO), 0.0, 1.0
	)
	return 1.0 - reduction

func _is_broken(factor: float) -> bool:
	return factor >= 1.0 - BREAK_EPSILON

func _visual_strength() -> float:
	return clampf((1.0 - _factor) / FULL_HP_REDUCTION, 0.0, 1.0)

func _apply_factor(new_factor: float, update_visual: bool = true) -> void:
	if stats == null or not is_instance_valid(stats):
		return
	var old_strength := _visual_strength()
	var old_factor := _factor if _factor > 0.0 else 1.0
	stats.global_hurt_damage_mult = stats.global_hurt_damage_mult / old_factor * new_factor
	_factor = new_factor
	stats.update_body_ability()
	if update_visual:
		_update_visual(old_strength, _visual_strength())

func _update_visual(old_strength: float, new_strength: float) -> void:
	if new_strength <= 0.0:
		if old_strength > 0.0:
			if _bar != null and is_instance_valid(_bar):
				_bar.play_break()
			_spawn_break_effect()
			if not Engine.is_editor_hint():
				SoundManager.play_sfx(ARMOR_BREAK_SFX)
		return
	if _bar == null or not is_instance_valid(_bar):
		return
	_bar.set_strength(new_strength)
	if old_strength <= 0.0:
		_bar.appear()

func _attach_bar() -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.has_method("add_overhead_item"):
		return
	if _bar != null and is_instance_valid(_bar):
		return
	var bar := ARMOR_BAR_SCENE.instantiate() as Control
	if bar == null:
		return
	add_child(bar)
	bar.set_strength(0.0)
	bar.visible = false
	if not body.add_overhead_item(bar):
		bar.queue_free()
		return
	_bar = bar

func _detach_bar() -> void:
	if _bar == null:
		return
	if is_instance_valid(_bar):
		if body != null and is_instance_valid(body) and body.has_method("remove_overhead_item"):
			body.remove_overhead_item(_bar)
		_bar.queue_free()
	_bar = null

func _spawn_break_effect() -> void:
	if body == null or not is_instance_valid(body) or not (body is Node2D):
		return
	var effect := ARMOR_BREAK_SCENE.instantiate()
	if effect == null:
		return
	body.add_child(effect)
	if effect is Node2D:
		(effect as Node2D).global_position = (body as Node2D).global_position + Vector2(0.0, -6.0)

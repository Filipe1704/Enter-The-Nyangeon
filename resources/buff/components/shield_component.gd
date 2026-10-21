extends BuffComponent

@export var base_hits: int = 10
@export var growth_per_round: int = 2
@export var max_hits: int = 40
@export var effect_scene: PackedScene = preload("res://scenes/debuff/shield_effect.tscn")

var resource: Buff
var stats: EnemyStats
var effect: Node2D
var active: bool = false

func activate(entry: Dictionary) -> void:
	if active:
		return
	resource = entry["resource"]
	stats = body.get("stats") if body != null else null
	if stats == null:
		return
	var hits := hits_for_round(maxi(1, int(PlayerData.now_round)))
	if hits <= 0:
		return
	active = true
	stats.shield_active = true
	stats.shield_max_hits = hits
	stats.shield_hits = hits
	if not stats.shield_broken.is_connected(_on_shield_broken):
		stats.shield_broken.connect(_on_shield_broken)
	if effect_scene != null and body is Node2D:
		effect = effect_scene.instantiate() as Node2D
		if effect != null:
			body.add_child(effect)
			effect.z_index = 1
			effect.fit_to_enemy(body)

func deactivate() -> void:
	if effect != null and is_instance_valid(effect):
		effect.queue_free()
	effect = null
	if stats != null and is_instance_valid(stats):
		if stats.shield_broken.is_connected(_on_shield_broken):
			stats.shield_broken.disconnect(_on_shield_broken)
		stats.reset_shield()
	stats = null
	resource = null
	active = false

func hits_for_round(round_index: int) -> int:
	return clampi(base_hits + growth_per_round * maxi(0, round_index - 1), 0, max_hits)

func _on_shield_broken() -> void:
	if not active:
		return
	active = false
	if manager != null and resource != null and manager.has_method("remove_buff"):
		manager.remove_buff(resource)

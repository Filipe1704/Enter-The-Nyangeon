extends FireFieldBase

var hp_mult: float = 0.05
var damage_count: int = 0
var player: Node

# 玩家会在换角色时被销毁重建；火场长期存活，取用前统一重新解析（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

func _on_field_ready() -> void:
	is_ready = true
	GameEvents.round_end.connect(idle_state)
	active_state()
	player = PlayerRef.resolve(self)

func _field_lifetime() -> int:
	return 30

func _on_field_activated() -> void:
	damage_count = 0

func _on_field_expired() -> void:
	time_length = 30
	idle_state()

func add_damage_data():
	var p := _ensure_player()
	if p == null:
		return
	for i in body_group:
		if i == null or not is_instance_valid(i):
			continue
		var body = i.owner
		if body == null or not is_instance_valid(body):
			continue
		var damage_value: int
		if damage_count < 8:
			damage_value = 8 * p.stats.fire_dot_layer * p.stats.dot_damage * p.stats.global_damage
		else:
			damage_count = 0
			damage_value = body.stats.max_hp * hp_mult
			if body.is_in_group("BOSS"):
				damage_value = body.stats.max_hp * 0.01
		hit_box.damage_data.base_damage = damage_value
		hit_box.damage_data.flags.append(GameTags.TRUE_DAMAGE)
		i.hit_received.emit(hit_box.damage_data)
		if is_instance_valid(body) and body.get("enemy_buff_manager") != null:
			body.enemy_buff_manager.apply_buff(enemy_buff, value)
		damage_count += 1

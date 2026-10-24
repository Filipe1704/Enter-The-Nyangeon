extends FireFieldBase

# 莲华人偶专用火场：参考 scenes/debuff/fire_field.gd，
# 但伤害为道具侧给定的固定值（无最大生命值百分比伤害）。
# is_idle / idle_state / active_state 供 renge_doll 的内置池复用。

@export var life_ticks: int = 20

var field_damage: int = 0

func _field_lifetime() -> int:
	return life_ticks

func _damage_source() -> String:
	return GameTags.EQUIP

func add_damage_data():
	if body_group.is_empty():
		return
	for i in body_group:
		if i == null or not is_instance_valid(i):
			continue
		hit_box.damage_data.base_damage = field_damage
		if not hit_box.damage_data.flags.has(GameTags.TRUE_DAMAGE):
			hit_box.damage_data.flags.append(GameTags.TRUE_DAMAGE)
		i.hit_received.emit(hit_box.damage_data)
		var body = i.owner
		if enemy_buff != null and body != null and is_instance_valid(body) and body.get("enemy_buff_manager") != null:
			body.enemy_buff_manager.apply_buff(enemy_buff, value)

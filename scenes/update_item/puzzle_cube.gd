extends EquipItem

@onready var follow_icon = preload("res://scenes/update_item/puzzle_cube_icon.tscn")

var overflow_count: int = 0
var overflow_cd: int = 0

var damage_data: DamageData

func _on_equip():
	GameEvents.enemy_over_kill_damage.connect(dead_overflow_damage)
	GameEvents.global_time_count.connect(time_count)
	damage_data = DamageData.new()
	attach_follow_icon(follow_icon)

func time_count():
	if overflow_cd > 0:
		overflow_cd -= 1
		if overflow_cd <= 0:
			overflow_count_add()

func overflow_count_add():
	var target: Node = PoolManager.get_random_active_enemy()
	if target != null:
		var true_damage: int = overflow_count
		target.health_component.request_extra_damage(DamageData.true_hit(true_damage, GameTags.EQUIP, self))

func dead_overflow_damage(overkill_damage: int, _taken_damage_data: DamageData, _body_path: NodePath):
	if overflow_cd <= 0:
		overflow_count = clamp(overkill_damage, 1, 9223372036854775807)
		overflow_cd = 1

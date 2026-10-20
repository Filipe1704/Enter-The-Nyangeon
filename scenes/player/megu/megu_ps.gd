extends PlayerPS

@onready var fire_field = preload("res://scenes/debuff/fire_field.tscn")

const FIRE_FIELD_CD_TICKS: int = 3
const FIRE_FIELD_CAP: int = 21

var value: Array
var fire_group: Array[Node]
var ps_luck: int = 20
var fire_field_cd: int = 0

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	PlayerData.set_player.connect(set_playerdata)
	if not GameEvents.global_time_count.is_connected(_tick_fire_field_cd):
		GameEvents.global_time_count.connect(_tick_fire_field_cd)
	player.damage_types.append(GameTags.FIRE_DAMAGE)

func _tick_fire_field_cd():
	if fire_field_cd > 0:
		fire_field_cd -= 1

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		ps_luck = 20
		GameEvents.player_bullet_free_position.connect(add_fire_field)
		pass
	elif now_t == 2:
		PlayerData.fire_dot_layer_add += 6
		PlayerData.update_player_ability()
	elif now_t == 3:
		GameEvents.player_shot_position.connect(add_fire_bullet)

func set_playerdata():
	PlayerData.bullet_damage_mult = 0.4

func add_fire_bullet(_shoot_position: Vector2, bullet: Node):
	if bullet.get("can_block") != null:
		bullet.can_block = false

func add_fire_field(free_position: Vector2):
	if fire_field_cd > 0:
		return
	var luck = randf_range(0, 200)
	if luck < ps_luck + stats.luck:
		var ins = _take_fire_field()
		if ins == null:
			return
		ins.global_position = free_position
		ins.active_state()
		fire_field_cd = FIRE_FIELD_CD_TICKS

func _take_fire_field() -> Node:
	for f in fire_group:
		if is_instance_valid(f) and f.is_inside_tree() and f.is_idle == 1:
			return f
	if fire_group.size() >= FIRE_FIELD_CAP:
		return null
	var ins = fire_field.instantiate()
	get_tree().get_first_node_in_group("SELayer").call_deferred("add_child", ins)
	fire_group.push_back(ins)
	return ins

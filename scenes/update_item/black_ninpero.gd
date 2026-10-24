extends EquipItem

@export var enemy_buff: Buff
@onready var black_ninpero_icon = preload("res://scenes/update_item/black_ninpero_icon.tscn")

var value: Array = []

@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float


func _on_equip():
	player = get_tree().get_first_node_in_group("Player")

	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.bullet_speed_mult *= 1.05
	attach_follow_icon(black_ninpero_icon)

func _setup():
	GameEvents.enemy_damage_taken.connect(add_buff)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	buff_layer += 25
	buff_value *= 1
	buff_erase_timer *= 1
	value = [buff_layer, buff_value, buff_erase_timer]

func add_buff(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		var body: Node = get_node_or_null(body_path)
		if body != null:
			body.enemy_buff_manager.apply_buff(enemy_buff, value)

extends EquipItem

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var flammable_explosives_icon = preload("res://scenes/update_item/flammable_explosives_icon.tscn")
var value: Array = []
var add_layer: int

func _on_equip():
	value = [buff_layer, buff_value, buff_erase_timer]
	add_layer = 1
	attach_follow_icon(flammable_explosives_icon)

func _setup():
	GameEvents.enemy_damage_taken.connect(fire_explosion)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	value = [buff_layer, buff_value, buff_erase_timer]
	add_layer += 1

func fire_explosion(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.EXPLOSION_DAMAGE):
		var enemy_body: Node = get_node_or_null(body_path)
		if enemy_body == null:
			return
		for i in add_layer:
			enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)

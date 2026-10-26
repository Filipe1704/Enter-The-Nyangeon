extends EquipItem

@onready var follow_icon = preload("res://scenes/update_item/peroro_kagami_mochi_icon.tscn")

func _on_equip():
	GameEvents.explosion_quantity.connect(add_damage_mult)
	attach_follow_icon(follow_icon)

func add_damage_mult(size: int, explosion: Node):
	var mult_value = size * 0.1 + 1
	explosion.damage_data.base_damage *= mult_value

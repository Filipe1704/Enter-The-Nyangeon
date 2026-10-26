extends EquipItem

@onready var voodoo_doll_icon = preload("res://scenes/update_item/voodoo_doll_icon.tscn")

func _on_equip():
	PlayerData.bullet_damage_mult += 0.5
	PlayerData.hurt_mult_mult += 0.5
	attach_follow_icon(voodoo_doll_icon)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_mult += 0.5
	PlayerData.hurt_mult_mult += 0.5

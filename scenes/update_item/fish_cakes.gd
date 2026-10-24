extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.equip_damage_mult += 0.35
	PlayerData.dot_damage_mult += 0.35

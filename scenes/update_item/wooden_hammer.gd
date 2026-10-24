extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.critical_luck_mult *= 0.5
	PlayerData.global_damage_mult += 0.5

extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.dot_damage_mult += 0.5
	PlayerData.dot_time_mult -= 0.25

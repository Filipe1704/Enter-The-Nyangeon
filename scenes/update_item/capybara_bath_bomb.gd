extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.dot_damage_mult += 0.18

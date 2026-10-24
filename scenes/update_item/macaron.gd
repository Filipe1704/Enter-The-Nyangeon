extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.max_hp_mult += 1
	PlayerData.hurt_mult_mult += 1

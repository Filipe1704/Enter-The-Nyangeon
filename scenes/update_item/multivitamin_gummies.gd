extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.max_t_hp_mult += 0.15

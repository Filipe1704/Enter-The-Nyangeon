extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.explosion_range_mult += 0.25

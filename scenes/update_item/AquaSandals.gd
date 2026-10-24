extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.MAX_SPEED_mult += 0.1

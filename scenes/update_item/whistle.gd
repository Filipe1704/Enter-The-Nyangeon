extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.bullet_speed_mult += 0.15

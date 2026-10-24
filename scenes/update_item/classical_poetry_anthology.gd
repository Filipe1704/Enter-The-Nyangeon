extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.hurt_resis_add += 15
	PlayerData.MAX_SPEED_mult -= 0.1

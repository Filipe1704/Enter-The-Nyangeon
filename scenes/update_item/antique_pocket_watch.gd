extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.critical_luck_add += 3
	PlayerData.luck_add += 10

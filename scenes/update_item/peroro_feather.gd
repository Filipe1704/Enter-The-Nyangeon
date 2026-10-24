extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.luck_add += 12

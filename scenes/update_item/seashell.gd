extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.critical_damage_add += 0.12

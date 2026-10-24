extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.summoned_damage_add += 0.2

extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.luck_add += 28
	PlayerData.bullet_damage_mult -= 0.05

extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.max_ammo_add += 15
	PlayerData.bullet_damage_mult -= 0.05

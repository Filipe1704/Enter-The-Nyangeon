extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.max_hp_mult -= 0.12
	PlayerData.bullet_damage_mult += 0.3

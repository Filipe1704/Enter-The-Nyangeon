extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.bullet_knockback_mult += 0.23
	PlayerData.bullet_damage_mult += 0.12

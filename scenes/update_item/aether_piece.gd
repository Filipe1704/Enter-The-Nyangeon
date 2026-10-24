extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.bullet_shoot_time_mult -= 0.06
	PlayerData.bullet_damage_mult += 0.15

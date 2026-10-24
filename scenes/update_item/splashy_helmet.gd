extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.hurt_resis_add += 2
	PlayerData.bullet_damage_mult -= 0.05

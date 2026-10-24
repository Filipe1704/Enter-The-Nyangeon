extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.explosion_damage_mult += 0.15

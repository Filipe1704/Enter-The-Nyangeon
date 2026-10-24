extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.max_hp_mult -= 0.2
	PlayerData.explosion_damage_mult += 0.4

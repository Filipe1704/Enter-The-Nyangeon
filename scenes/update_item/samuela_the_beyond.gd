extends EquipItem

# 萨缪尔·彼方：+60% 召唤物伤害，-20% 子弹伤害。最大持有 3 个。

func _apply_effect(_quantity: int):
	PlayerData.summoned_damage_add += 0.6
	PlayerData.bullet_damage_mult -= 0.2

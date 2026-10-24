extends "res://script/dot_diffuse.gd"

func fire_dot_add():
	if !enemy_group.is_empty():
		value = [buff_layer, buff_value, buff_erase_timer]
		for i in range(enemy_group.size() - 1, -1, -1):
			var enemy = enemy_group[i]
			if enemy == null or not is_instance_valid(enemy):
				enemy_group.remove_at(i)
				continue
			enemy.enemy_buff_manager.apply_buff(enemy_buff, value)
		
		_show_spread_text(Color(1, 0.367, 0.178))


func _apply_diffusion():
	fire_dot_add()

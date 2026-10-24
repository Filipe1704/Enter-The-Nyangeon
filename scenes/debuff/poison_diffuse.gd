extends "res://script/dot_diffuse.gd"

var enemy_num: int = 0
var diffuse_num: int = 0

func poison_dot_add():
	if !enemy_group.is_empty():
		for i in range(enemy_group.size() - 1, -1, -1):
			if enemy_group[i] == null or not is_instance_valid(enemy_group[i]):
				enemy_group.remove_at(i)
		
		var i_num: int
		if enemy_num < enemy_group.size():
			i_num = enemy_num
		else:
			i_num = enemy_group.size()
		
		for i in i_num:
			var has_tag = enemy_group[i].stats.tag_set.has("poison_diffuse")
			if !has_tag:
				enemy_group[i].stats.tag_set["poison_diffuse"] = {
					"resource": "poison_diffuse",
					"quantity": diffuse_num
				}
			value = [buff_layer, buff_value, buff_erase_timer]
			enemy_group[i].enemy_buff_manager.apply_buff(enemy_buff, value)
		
		_show_spread_text(Color(0.063, 0.54, 0.342))

func sort_enemy():
	if !enemy_group.is_empty():
		for i in range(enemy_group.size() - 1, -1, -1):
			if enemy_group[i] == null or not is_instance_valid(enemy_group[i]):
				enemy_group.remove_at(i)
		enemy_group.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func _targets_changed():
	sort_enemy()


func _apply_diffusion():
	poison_dot_add()

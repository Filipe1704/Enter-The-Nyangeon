class_name BossSpawner
extends Node

# Boss 生成统一入口：回合开始与后续中途加入都走这里。
const SPAWN_ANIM: PackedScene = preload("res://script/spawn_anim.tscn")

func spawn(card: BossCard, position: Vector2 = Vector2.ZERO, multipliers: Dictionary = {}) -> bool:
	if card == null or card.body == null:
		push_warning("[BossSpawner] BossCard 缺 body")
		return false
	var pos := position
	if pos == Vector2.ZERO:
		var center := get_tree().get_first_node_in_group("CenterPosition")
		if center is Node2D:
			pos = (center as Node2D).global_position
	var spawn_anim = PoolManager.get_pool("spawn_anim")
	if spawn_anim == null or spawn_anim.is_idle == 0:
		spawn_anim = SPAWN_ANIM.instantiate()
		var root := get_tree().get_first_node_in_group("EnemiesRoot")
		if root == null:
			root = get_tree().current_scene
		root.add_child(spawn_anim)
	spawn_anim.position = pos
	spawn_anim.hp_mult = float(multipliers.get("hp", 1.0))
	spawn_anim.damage_mult = float(multipliers.get("damage", 1.0))
	spawn_anim.is_boss = true
	spawn_anim.controller_managed = true
	spawn_anim.can_spawn = true
	spawn_anim.active_state()
	spawn_anim.enemy_spawn_anim(card)
	return true

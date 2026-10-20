extends Node2D

const DEATH_GPU = preload("res://script/death_gpu.tscn")

@export var stats: EnemyStats
@export var y_position = 15

var sprite: String
var parent_node
var spawn_position: Vector2
var texture

func _ready():
	stats.is_dead.connect(on_death_anim)
	parent_node = get_parent()
	sprite = parent_node.icon
	spawn_position = Vector2.UP * y_position
	parent_node.is_dead.connect(on_death_anim)
	texture = load("res://sprites/enemies/" + sprite + ".png")
	

func on_death_anim(play_sound: bool = true):
	var root = get_tree().get_first_node_in_group("EnemiesRoot")
	spawn_effect(root, global_position + spawn_position, texture, play_sound)

# 清场复用：不播放死亡音效，只生成与正常死亡一致的粒子。
static func spawn_for_enemy(enemy: Node, play_sound: bool = true) -> Node2D:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var root = enemy.get_tree().get_first_node_in_group("EnemiesRoot")
	var pos: Vector2 = enemy.global_position + Vector2.UP * 15.0
	return spawn_effect(root, pos, _resolve_texture(enemy), play_sound)

static func spawn_effect(root: Node, world_position: Vector2, icon_texture: Texture2D, play_sound: bool = true) -> Node2D:
	if root == null:
		return null
	var ins = DEATH_GPU.instantiate()
	root.add_child(ins)
	ins.global_position = world_position
	if icon_texture != null:
		ins.gpu_particles_2d.texture = icon_texture
	ins.animation_player.play("death")
	if play_sound:
		SoundManager.play_sfx("DeadSounds")
	return ins

static func _resolve_texture(enemy: Node) -> Texture2D:
	var icon_name := str(enemy.get("icon"))
	if icon_name != "":
		var icon_path := "res://sprites/enemies/%s.png" % icon_name
		if ResourceLoader.exists(icon_path):
			return load(icon_path) as Texture2D
	var pool_id := str(enemy.get("pool_id"))
	if pool_id != "":
		var pool_icon_path := "res://sprites/enemies/%s_icon.png" % pool_id
		if ResourceLoader.exists(pool_icon_path):
			return load(pool_icon_path) as Texture2D
	return null

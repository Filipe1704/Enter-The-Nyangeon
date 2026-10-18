extends Node

## 内部道具纯视觉驱动：位置/瞄准来自镜像玩家，绕行与动画来自拥有者快照。
## 由 CoopItemVisuals.build_internal_visual 挂到视觉根节点下。

const ItemState := preload("res://mods/etn_coop/net/coop_item_state.gd")

var mirror: Node = null
var item_id: String = ""
var visual: Node = null
var orbit_speed: float = 0.0


func setup(p_mirror: Node, p_item_id: String, p_visual: Node) -> void:
	mirror = p_mirror
	item_id = p_item_id
	visual = p_visual
	set_process(true)


func _process(delta: float) -> void:
	if mirror == null or not is_instance_valid(mirror):
		return
	if visual == null or not is_instance_valid(visual):
		return
	var sprite = mirror.get("sprite_2d")
	var gfx = mirror.get("graphics")
	match item_id:
		"kitchen_knife":
			if gfx is Node2D and visual is Node2D:
				(visual as Node2D).scale.x = (gfx as Node2D).scale.x
			var knife = visual.get_node_or_null("knife")
			if knife is Node2D:
				if sprite is Node2D:
					(knife as Node2D).position.y = (sprite as Node2D).position.y + 3.0
				var aim = mirror.get("crosshair_pos")
				if aim is Vector2 and not aim.is_equal_approx((knife as Node2D).global_position):
					(knife as Node2D).look_at(aim)
		"little_kei":
			var follow := visual.get_node("Path2D/PathFollow2D") as PathFollow2D
			follow.progress_ratio = wrapf(follow.progress_ratio + orbit_speed * Engine.physics_ticks_per_second * delta, 0.0, 1.0)
		"spiked_shell":
			var asp = visual.get_node_or_null("AnimatedSprite2D")
			if asp is Node2D and sprite is Node2D:
				(asp as Node2D).position.y = (sprite as Node2D).position.y
		"life_jacket":
			var n2 = visual.get_node_or_null("Node2D2")
			if n2 is Node2D and sprite is Node2D:
				(n2 as Node2D).position = (sprite as Node2D).position


func apply_state(state: Dictionary) -> void:
	if not is_instance_valid(visual):
		return
	if item_id == "little_kei":
		visual.get_node("Path2D/PathFollow2D").progress_ratio = state.phase
		orbit_speed = state.speed
		visual.get_node("Path2D/PathFollow2D/Kei/Area2D").scale = Vector2.ONE * state.scale
		visual.get_node("Path2D/PathFollow2D/Kei/Sprite2D").scale.x = state.facing
	elif item_id == "life_jacket":
		visual.get_node("Node2D2").visible = state.shield
	var paths: Array = ItemState.ANIMATION_PATHS.get(item_id, [])
	for i in range(paths.size()):
		var ap := visual.get_node_or_null(paths[i]) as AnimationPlayer
		var animation: Array = state.animations[i]
		if ap == null:
			continue
		if animation.is_empty():
			ap.stop()
			continue
		var anim_name: String = animation[0]
		if not ap.has_animation(anim_name):
			continue
		if ap.assigned_animation != anim_name or (animation[2] and not ap.is_playing()):
			ap.play(anim_name)
		ap.seek(minf(animation[1], ap.get_animation(anim_name).length), true)
		if not animation[2]:
			ap.pause()

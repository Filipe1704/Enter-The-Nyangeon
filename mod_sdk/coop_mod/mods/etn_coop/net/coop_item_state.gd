extends RefCounted

## 只传送内部道具的显示状态；不发送 Buff、伤害或可执行的方法/节点路径。
const ANIMATION_PATHS := {
	"little_kei": ["Path2D/PathFollow2D/Kei/Area2D/AnimatedSprite2D/AnimationPlayer2"],
	"life_jacket": ["Node2D/AnimationPlayer", "Node2D2/AnimationPlayer"],
	"ginseng_doll": ["Node2D/AnimationPlayer"],
	"energy_supplement": ["Node2D/AnimationPlayer"],
}


static func capture(player: Node) -> Dictionary:
	var states: Dictionary = {}
	for item in player.get_children():
		if not (item is EquipItem):
			continue
		var id: String = item.item_id
		if not ANIMATION_PATHS.has(id):
			continue
		var state: Dictionary = {"animations": []}
		for path in ANIMATION_PATHS[id]:
			var ap := item.get_node_or_null(path) as AnimationPlayer
			if ap == null or ap.assigned_animation == "":
				state.animations.append([])
			else:
				state.animations.append([str(ap.assigned_animation), ap.current_animation_position, ap.is_playing()])
		if id == "little_kei":
			state["phase"] = item.path_follow_2d.progress_ratio
			state["speed"] = item.kei_velocity
			state["scale"] = item.area_2d.scale.x
			state["facing"] = item.sprite_2d.scale.x
		elif id == "life_jacket":
			state["shield"] = item.node_2d_2.visible
		states[id] = state
	return sanitize(states)


static func _number(value, fallback: float, low: float, high: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), low, high)


static func sanitize(states: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	# 迭代固定清单，不遍历或保留远端提供的任意字段。
	for id in ANIMATION_PATHS:
		var raw = states.get(id)
		if not (raw is Dictionary):
			continue
		var state: Dictionary = {"animations": []}
		var animations = raw.get("animations", [])
		for i in range(ANIMATION_PATHS[id].size()):
			var anim = animations[i] if animations is Array and i < animations.size() else []
			if anim is Array and anim.size() == 3 and anim[0] is String \
					and anim[0] in ["RESET", "new_animation"] and anim[2] is bool:
				state.animations.append([anim[0], _number(anim[1], 0.0, 0.0, 30.0), anim[2]])
			else:
				state.animations.append([])
		if id == "little_kei":
			state["phase"] = _number(raw.get("phase"), 0.0, 0.0, 1.0)
			state["speed"] = _number(raw.get("speed"), 0.003, 0.0, 0.024)
			state["scale"] = _number(raw.get("scale"), 1.0, 0.01, 64.0)
			state["facing"] = -1.0 if _number(raw.get("facing"), 1.0, -1.0, 1.0) < 0.0 else 1.0
		elif id == "life_jacket":
			var shield = raw.get("shield", false)
			state["shield"] = shield if shield is bool else false
		clean[id] = state
	return clean

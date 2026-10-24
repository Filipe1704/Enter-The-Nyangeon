class_name HurtBoxMeasure
extends RefCounted

## 从实体上测量 HurtBox 形状的世界尺寸与本地方位的共享工具。
## shield_effect / frenzy_effect 的视觉适配共用此测量，形状节点按三级回退解析。

## 返回 {"size": Vector2（含节点缩放补偿）, "center": Vector2（body 本地坐标）}；
## 找不到形状时返回以 fallback_diameter 为边长的正方形、中心为零。
static func measure(body: Node, fallback_diameter: float) -> Dictionary:
	var shape_node: Node = body.get("hurt_box_shape_2d")
	if shape_node == null:
		shape_node = body.get_node_or_null("HurtBox/HurtBoxShape2D")
	if shape_node == null:
		shape_node = body.get("collision_shape_2d")
	if shape_node == null or not is_instance_valid(shape_node) or not (shape_node is Node2D):
		return {"size": Vector2(fallback_diameter, fallback_diameter), "center": Vector2.ZERO}
	var shape = shape_node.get("shape")
	if shape == null:
		return {"size": Vector2(fallback_diameter, fallback_diameter), "center": Vector2.ZERO}
	var size := Vector2.ZERO
	if shape is RectangleShape2D:
		size = (shape as RectangleShape2D).size
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		size = Vector2(radius * 2.0, radius * 2.0)
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		size = Vector2(capsule.radius * 2.0, capsule.height)
	if size == Vector2.ZERO:
		return {"size": Vector2(fallback_diameter, fallback_diameter), "center": Vector2.ZERO}
	var scale_factor := (shape_node as Node2D).global_transform.get_scale().abs()
	return {
		"size": size * scale_factor,
		"center": body.to_local((shape_node as Node2D).global_position),
	}

extends Node2D

const SHARD_COUNT := 12
const LIFETIME := 0.55
const RING_TEXTURE: Texture2D = preload("res://sprites/particle/circular_1.png")
const SHARD_COLORS := [
	Color("#5f8fb8"),
	Color("#9cc6e6"),
	Color("#eaf6ff"),
]

func _ready() -> void:
	z_index = 5
	_spawn_ring()
	_spawn_shards()
	get_tree().create_timer(LIFETIME, false).timeout.connect(queue_free)

func _spawn_ring() -> void:
	var ring := Sprite2D.new()
	ring.texture = RING_TEXTURE
	ring.modulate = Color(0.72, 0.9, 1.0, 0.95)
	ring.scale = Vector2(0.35, 0.35)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = material
	add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.35, 1.35), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.25).set_delay(0.05)

func _spawn_shards() -> void:
	for i in range(SHARD_COUNT):
		var shard := Polygon2D.new()
		var width := randf_range(2.0, 4.5)
		var height := randf_range(1.5, 3.5)
		shard.polygon = PackedVector2Array([
			Vector2(-width, -height),
			Vector2(width * 0.8, -height * 0.7),
			Vector2(width, height),
			Vector2(-width * 0.7, height * 0.8),
		])
		shard.color = SHARD_COLORS[i % SHARD_COLORS.size()]
		shard.rotation = randf_range(-PI, PI)
		add_child(shard)
		var angle := randf_range(-PI, PI)
		var distance := randf_range(18.0, 42.0)
		var target := Vector2.RIGHT.rotated(angle) * distance + Vector2(0.0, 8.0)
		var spin := randf_range(-7.0, 7.0)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", target, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", shard.rotation + spin, 0.36)
		tween.tween_property(shard, "scale", Vector2(0.35, 0.35), 0.36)
		tween.tween_property(shard, "modulate:a", 0.0, 0.24).set_delay(0.12)

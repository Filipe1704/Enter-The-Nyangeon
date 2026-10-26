extends Node2D

var dir: Vector2 = Vector2.ZERO

var speed: float
var accel: float
var speed_time: float = 0.1

var velocity: Vector2 = Vector2.ZERO

var follow_mark: Marker2D

@onready var sprite_2d = $Sprite2D

func get_follow(follow: Marker2D):
	if follow == null or not is_instance_valid(follow):
		return
	follow_mark = follow
	global_position = follow_mark.global_position

func _physics_process(delta):
	# 挂点可能先于图标释放（道具/玩家被清、链上游图标被回收），失效后停住而不是报错。
	if follow_mark == null or not is_instance_valid(follow_mark):
		return
	speed = min(650, global_position.distance_to(follow_mark.global_position) * 1.3 * global_position.distance_to(follow_mark.global_position) / 5)
	accel = speed / speed_time
	
	if global_position.distance_to(follow_mark.global_position) < 5:
		dir = Vector2.ZERO
	else:
		dir =(follow_mark.global_position - self.global_position).normalized()
	
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir.y * speed, accel * delta)
	
	if velocity.x > 0:
		sprite_2d.scale.x = 1
	elif velocity.x < 0:
		sprite_2d.scale.x = -1
	
	global_position += velocity * delta

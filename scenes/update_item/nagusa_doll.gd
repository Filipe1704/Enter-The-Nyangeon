extends EquipItem

@onready var nagusa_doll_icon: PackedScene = preload("res://scenes/update_item/nagusa_doll_icon.tscn")
@onready var chill_ring_scene: PackedScene = preload("res://scenes/bullet/chill_ring.tscn")

@export var chill_layer_cap: int = 5

var doll: Node
var add_layer: int = 1
var ring: Node
var tick: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	spawn_doll()

func _setup():
	GameEvents.global_time_count.connect(_time_count)

func _apply_effect(quantity: int):
	chill_layer_cap = 5 + quantity

func spawn_doll():
	if player == null:
		return
	doll = attach_follow_icon(nagusa_doll_icon)

func _time_count():
	tick += 1
	if tick < 5:
		return
	tick = 0
	_cast_ring()

func _cast_ring():
	if doll == null or not is_instance_valid(doll):
		return
	if ring == null or not is_instance_valid(ring):
		ring = chill_ring_scene.instantiate()
		get_tree().get_first_node_in_group("SELayer").add_child(ring)
	ring.add_layer = add_layer
	ring.chill_layer_cap = chill_layer_cap * player.stats.chill_layer_mult
	ring.source_id = item_id
	ring.global_position = doll.global_position
	ring.active_state()
	ExtensionHooks.notify_named("on_visual_activated", [ring])

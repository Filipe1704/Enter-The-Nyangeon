extends HSlider

@export var bus: StringName = "Master"
@export var value_label_path: NodePath

@onready var bus_index := AudioServer.get_bus_index(bus)
@onready var value_label: Label = get_node_or_null(value_label_path) as Label

var isDrag: bool = false
var start_pos: float = 0

func _ready():
	
	gui_input.connect(set_scrollbox_gui_input)
	
	value = SoundManager.get_volume(bus_index)
	_update_value_label(value)
	
	value_changed.connect(func (v: float):
		_update_value_label(v)
		SoundManager.set_volume(bus_index, v)
		Game.save_config()
		)

func _update_value_label(current_value: float) -> void:
	if value_label != null:
		value_label.text = "%d%%" % roundi(current_value * 100)

func set_scrollbox_gui_input(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		isDrag = true
		start_pos = event.position.x
	
	if event as InputEventScreenTouch and !event.pressed:
		isDrag = false
		start_pos = 0
	
	if isDrag == true:
		var offset = (event.position.x - start_pos) * 0.01
		self.value += offset
		start_pos = event.position.x

extends PanelContainer

@export var button_name: String
@export var button_type: String
@export var toggle_mode: bool

@onready var color_rect: ColorRect = $ColorRect
@onready var button_name_label: Label = $button_name
@onready var sprite_2d: Sprite2D = $ColorRect/Sprite2D

const TAP_DISTANCE: float = 10.0
var _touch_index: int = -1
var _touch_start: Vector2
var _touch_dragged: bool = false
var player_card: PlayerCard


var is_selected: bool = false
var _revealed_path: String = ""

func _ready() -> void:
	self.gui_input.connect(button_pressed)
	self.mouse_entered.connect(mouse_in)
	self.mouse_exited.connect(mouse_out)
	update_button()

func update_button():
	if button_type == "normal_sort":
		button_name_label.text = "button_" + button_name
		sprite_2d.texture = null
	elif button_type == "character":
		if player_card != null:
			button_name = player_card.id
			button_name_label.text = player_card.id
		else:
			button_name_label.text = button_name
		sprite_2d.texture = null
	elif button_type == "gamemode":
		if button_name != "null":
			button_name_label.text = button_name + "_id"
		else:
			button_name_label.text = button_name
		sprite_2d.texture = null

# 角色立绘按需加载/释放（列表可见性由 menu_box_character 调用）；幂等
func reveal() -> void:
	if button_type != "character" or player_card == null:
		return
	var p := player_card.sprite_path
	if _revealed_path == p and sprite_2d.texture != null:
		return
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
	sprite_2d.texture = LazyTexture.acquire(p)
	_revealed_path = p


func conceal() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""
	sprite_2d.texture = null


func _exit_tree() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""


func is_pressed():
	if toggle_mode == true:
		if is_selected == false:
			is_selected = true
			color_rect.color = Color(0.6,0.6,0.6)
		else:
			is_selected = false
			color_rect.color = Color(0.141,0.141,0.141)
	SoundManager.play_sfx("ButtonSounds")
	GameEvents.emit_scoreboard_select(button_name, button_type)

func is_null_pressed():
	is_selected = false
	color_rect.color = Color(0.141,0.141,0.141)

func _input(event: InputEvent) -> void:
	# 滚动容器可能消费拖动和释放，仍需更新本次手势状态。
	if event is InputEventScreenDrag and event.index == _touch_index:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if _touch_start.distance_to(local_position) > TAP_DISTANCE:
			_touch_dragged = true
	elif event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		_clear_touch.call_deferred(event.index)

func _clear_touch(index: int) -> void:
	if _touch_index == index:
		_touch_index = -1

func button_pressed(event: InputEvent):
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1:
				_touch_index = event.index
				_touch_start = event.position
				_touch_dragged = false
		elif event.index == _touch_index:
			var tapped: bool = not event.canceled and not _touch_dragged
			tapped = tapped and _touch_start.distance_to(event.position) <= TAP_DISTANCE
			tapped = tapped and Rect2(Vector2.ZERO, size).has_point(event.position)
			_touch_index = -1
			if tapped:
				is_pressed()
		return
	if event is InputEventScreenDrag:
		if event.index == _touch_index and _touch_start.distance_to(event.position) > TAP_DISTANCE:
			_touch_dragged = true
		return
	if event.is_action_pressed("shoot"):
		is_pressed()

func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	if is_selected == false:
		color_rect.color = Color(0.141,0.141,0.141)

func mouse_out():
	if is_selected == false:
		color_rect.color = Color(0.094,0.094,0.094)

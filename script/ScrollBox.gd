extends ScrollContainer

var isDrag: bool = false
var start_pos: float = 0
var _touch_index: int = -1

func _ready():
	gui_input.connect(set_scrollbox_gui_input)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_end_drag()
	)

func _end_drag() -> void:
	isDrag = false
	start_pos = 0
	_touch_index = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_drag()

func _input(event: InputEvent) -> void:
	if not isDrag:
		return
	# 即便释放发生在列表外或被其它 GUI 消费，也结束当前手势。
	if _touch_index == -1:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag()
		elif event is InputEventMouseMotion and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_end_drag()
	elif event is InputEventScreenTouch and event.index == _touch_index and not event.pressed:
		_end_drag()

func _drag_to(y: float) -> void:
	scroll_vertical -= y - start_pos
	start_pos = y

func set_scrollbox_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		# 滚轮只有按下事件，不能把它当成等待释放的拖动按键。
		if event.button_index != MOUSE_BUTTON_LEFT or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed and not isDrag:
			isDrag = true
			start_pos = event.position.y
		elif not event.pressed and _touch_index == -1:
			_end_drag()
	elif event is InputEventMouseMotion:
		if isDrag and _touch_index == -1 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_drag_to(event.position.y)
	elif event is InputEventScreenTouch:
		if event.pressed and not isDrag:
			isDrag = true
			_touch_index = event.index
			start_pos = event.position.y
		elif not event.pressed and event.index == _touch_index:
			_end_drag()
	elif event is InputEventScreenDrag and isDrag and event.index == _touch_index:
		_drag_to(event.position.y)

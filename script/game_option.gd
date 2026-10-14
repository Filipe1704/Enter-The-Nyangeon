extends OptionMenu

@onready var full_screen: Control = %FullScreen
@onready var shake: Control = %Shake
@onready var v_sync: Control = %VSync
@onready var damage_freq: HSlider = %DamageFreq
@onready var damage_freq_value: Label = %DamageFreqValue
@onready var effect_freq: HSlider = %EffectFreq
@onready var effect_freq_value: Label = %EffectFreqValue
@onready var hit_flash_freq: HSlider = %HitFlashFreq
@onready var hit_flash_freq_value: Label = %HitFlashFreqValue
@onready var resolutions_block: Control = %ResolutionsTouchBlock
@onready var mobile_notice = %MobileNotice
@onready var resolutions: OptionButton = %Resolutions
@onready var max_fps: HSlider = %MaxFps
@onready var max_fps_value: Label = %MaxFpsValue
@onready var physics_interp: Control = %PhysicsInterp

func _ready():
	setting_status()
	full_screen.mouse_entered.connect(mouse_on_full_screen)
	full_screen.mouse_exited.connect(mouse_out_full_screen)
	full_screen.gui_input.connect(mouse_selected_full_screen)
	shake.mouse_entered.connect(mouse_on_shake)
	shake.mouse_exited.connect(mouse_out_shake)
	shake.gui_input.connect(mouse_selected_shake)
	v_sync.mouse_entered.connect(mouse_on_vs)
	v_sync.mouse_exited.connect(mouse_out_vs)
	v_sync.gui_input.connect(mouse_selected_vs)
	physics_interp.mouse_entered.connect(mouse_on_physics_interp)
	physics_interp.mouse_exited.connect(mouse_out_physics_interp)
	physics_interp.gui_input.connect(mouse_selected_physics_interp)
	resolutions.item_selected.connect(_on_resolutions_item_selected)
	damage_freq.value_changed.connect(_on_damage_freq_value_changed)
	effect_freq.value_changed.connect(_on_effect_freq_value_changed)
	hit_flash_freq.value_changed.connect(_on_hit_flash_freq_value_changed)
	max_fps.value_changed.connect(_on_max_fps_value_changed)
	resolutions_block.gui_input.connect(_on_resolutions_touch_block_gui_input)
	resolutions_block.mouse_filter = (
		Control.MOUSE_FILTER_STOP if OS.has_feature("mobile") else Control.MOUSE_FILTER_IGNORE
	)
	for toggle in [full_screen, shake, v_sync, physics_interp]:
		toggle.focus_mode = Control.FOCUS_ALL
		var label: Label = toggle.get_parent().get_node("Label")
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	full_screen.focus_entered.connect(mouse_on_full_screen)
	full_screen.focus_exited.connect(mouse_out_full_screen)
	shake.focus_entered.connect(mouse_on_shake)
	shake.focus_exited.connect(mouse_out_shake)
	v_sync.focus_entered.connect(mouse_on_vs)
	v_sync.focus_exited.connect(mouse_out_vs)
	physics_interp.focus_entered.connect(mouse_on_physics_interp)
	physics_interp.focus_exited.connect(mouse_out_physics_interp)
	full_screen.get_parent().get_node("Label").gui_input.connect(mouse_selected_full_screen)
	shake.get_parent().get_node("Label").gui_input.connect(mouse_selected_shake)
	v_sync.get_parent().get_node("Label").gui_input.connect(mouse_selected_vs)
	physics_interp.get_parent().get_node("Label").gui_input.connect(mouse_selected_physics_interp)
	if OS.has_feature("mobile"):
		full_screen.get_parent().get_parent().hide()
		v_sync.get_parent().hide()
		physics_interp.get_parent().hide()

func menu_show():
	super()
	setting_status()

func _show_mobile_notice():
	mobile_notice.notice("option_mobile_only_notice")

func _on_resolutions_touch_block_gui_input(event: InputEvent):
	if event is InputEventScreenTouch and event.pressed:
		_show_mobile_notice()

func mouse_on_full_screen():
	if Game.on_full_screen == false:
		full_screen.get_node("AnimationPlayer").play("full_on")
	else:
		full_screen.get_node("AnimationPlayer").play("selected_out")

func mouse_out_full_screen():
	if Game.on_full_screen == false:
		full_screen.get_node("AnimationPlayer").play("full_out")
	else:
		full_screen.get_node("AnimationPlayer").play("selected")

func mouse_selected_full_screen(event: InputEvent):

	# 移动端由导出预设的沉浸式全屏接管，桌面端的窗口模式会关闭全屏、露出系统通知栏。
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			_show_mobile_notice()
		return

	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.on_full_screen == false:
			Game.on_full_screen = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			full_screen.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.on_full_screen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			full_screen.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

	if not event.is_echo() and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		full_screen.accept_event()
		SoundManager.play_sfx("ButtonSounds")
		if Game.on_full_screen == false:
			Game.on_full_screen = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			full_screen.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.on_full_screen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			full_screen.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

func mouse_on_shake():
	if Game.shake_screen == false:
		shake.get_node("AnimationPlayer").play("full_on")
	else:
		shake.get_node("AnimationPlayer").play("selected_out")

func mouse_out_shake():
	if Game.shake_screen == false:
		shake.get_node("AnimationPlayer").play("full_out")
	else:
		shake.get_node("AnimationPlayer").play("selected")

func mouse_selected_shake(event: InputEvent):

	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.shake_screen == false:
			Game.shake_screen = true
			shake.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.shake_screen = false
			shake.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

	if not event.is_echo() and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		shake.accept_event()
		SoundManager.play_sfx("ButtonSounds")
		if Game.shake_screen == false:
			Game.shake_screen = true
			shake.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.shake_screen = false
			shake.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

func mouse_on_vs():
	if Game.vsync_mode == false:
		v_sync.get_node("AnimationPlayer").play("full_on")
	else:
		v_sync.get_node("AnimationPlayer").play("selected_out")

func mouse_out_vs():
	if Game.vsync_mode == false:
		v_sync.get_node("AnimationPlayer").play("full_out")
	else:
		v_sync.get_node("AnimationPlayer").play("selected")

func mouse_selected_vs(event: InputEvent):

	# 移动端垂直同步由系统/驱动控制，避免桌面窗口设置生效。
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			_show_mobile_notice()
		return

	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.vsync_mode == false:
			Game.vsync_mode = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			v_sync.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.vsync_mode = false
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			v_sync.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

	if not event.is_echo() and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		v_sync.accept_event()
		SoundManager.play_sfx("ButtonSounds")
		if Game.vsync_mode == false:
			Game.vsync_mode = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			v_sync.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.vsync_mode = false
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			v_sync.get_node("AnimationPlayer").play("full_out")
			Game.save_config()


func mouse_on_physics_interp():
	if Game.physics_interp == false:
		physics_interp.get_node("AnimationPlayer").play("full_on")
	else:
		physics_interp.get_node("AnimationPlayer").play("selected_out")

func mouse_out_physics_interp():
	if Game.physics_interp == false:
		physics_interp.get_node("AnimationPlayer").play("full_out")
	else:
		physics_interp.get_node("AnimationPlayer").play("selected")

func mouse_selected_physics_interp(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		_toggle_physics_interp()

	if not event.is_echo() and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		physics_interp.accept_event()
		SoundManager.play_sfx("ButtonSounds")
		_toggle_physics_interp()

# 物理插值开关（默认关）：写入设置并运行期应用，随后持久化。
func _toggle_physics_interp():
	Game.physics_interp = not Game.physics_interp
	Game.apply_physics_interp()
	Game.save_config()
	if Game.physics_interp == true:
		physics_interp.get_node("AnimationPlayer").play("selected")
	else:
		physics_interp.get_node("AnimationPlayer").play("full_out")

func setting_status():
	if Game.on_full_screen == true:
		full_screen.get_node("AnimationPlayer").play("selected")
	else:
		full_screen.get_node("AnimationPlayer").play("full_out")

	resolutions.selected = Game.resolution

	if Game.shake_screen == true:
		shake.get_node("AnimationPlayer").play("selected")
	else:
		shake.get_node("AnimationPlayer").play("full_out")

	if Game.vsync_mode == true:
		v_sync.get_node("AnimationPlayer").play("selected")
	else:
		v_sync.get_node("AnimationPlayer").play("full_out")

	if Game.physics_interp == true:
		physics_interp.get_node("AnimationPlayer").play("selected")
	else:
		physics_interp.get_node("AnimationPlayer").play("full_out")

	damage_freq.set_value_no_signal(Game.damage_text_freq)
	damage_freq_value.text = _damage_freq_text(Game.damage_text_freq)
	effect_freq.set_value_no_signal(Game.effect_freq)
	effect_freq_value.text = _effect_freq_text(Game.effect_freq)
	hit_flash_freq.set_value_no_signal(Game.hit_flash_freq)
	hit_flash_freq_value.text = _effect_freq_text(Game.hit_flash_freq)
	max_fps.set_value_no_signal(Game.max_fps_index)
	max_fps_value.text = _max_fps_text(Game.max_fps_index)

func _on_resolutions_item_selected(index):
	var n: int
	# 移动端分辨率由设备决定，不能也不应改写窗口尺寸。
	if OS.has_feature("mobile"):
		return
	match index:
		0:
			DisplayServer.window_set_size(Vector2i(1280,720))
			n = 0
		1:
			DisplayServer.window_set_size(Vector2i(1600,900))
			n = 1
		2:
			DisplayServer.window_set_size(Vector2i(1920,1080))
			n = 2

	Game.resolution = n
	Game.save_config()

# 伤害数字频率滑条（设置项）：0=关 / 1=低 / 2=中 / 3=高 / 4=最高。
# 这里只负责写入档位与持久化；实际频率由 PoolManager 结合 FPS 自适应计算。
func _on_damage_freq_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, 4)
	if idx == Game.damage_text_freq:
		return
	Game.damage_text_freq = idx
	Game.save_config()
	damage_freq_value.text = _damage_freq_text(idx)

func _damage_freq_text(idx: int) -> String:
	match idx:
		0:
			return "0% · " + tr("damage_freq_off")
		1:
			return "25% · ≤2.5Hz"
		2:
			return "50% · ≤3.3Hz"
		3:
			return "75% · ≤5Hz"
	return "100% · ≤10Hz"

# 特效频率滑条（设置项）：0=关 / 1=×4间隔 / 2=×3 / 3=×2 / 4=×1(最高)。
# 写入档位后由 PoolManager 结合基准间隔与 FPS 自适应计算实际最短间隔（只降频率）。
func _on_effect_freq_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, 4)
	if idx == Game.effect_freq:
		return
	Game.effect_freq = idx
	Game.save_config()
	effect_freq_value.text = _effect_freq_text(idx)

func _effect_freq_text(idx: int) -> String:
	match idx:
		0:
			return "0% · " + tr("damage_freq_off")
		1:
			return "25% · ×4"
		2:
			return "50% · ×3"
		3:
			return "75% · ×2"
	return "100% · ×1"

# 受击闪白频率滑条（设置项）：独立于 effect_freq：0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1(最高)。
# 写入档位后由 PoolManager.hit_flash_allowed() 结合 60ms 基准与 FPS 自适应计算间隔。
func _on_hit_flash_freq_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, 4)
	if idx == Game.hit_flash_freq:
		return
	Game.hit_flash_freq = idx
	Game.save_config()
	hit_flash_freq_value.text = _effect_freq_text(idx)

# 帧率上限滑条（设置项）：0=无限制 / 1=60 / 2=75 / 3=90 / 4=120 / 5=144。
# 写入档位后立即应用 Engine.max_fps 并持久化。
func _on_max_fps_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, Game.FPS_CHOICES.size() - 1)
	if idx == Game.max_fps_index:
		return
	Game.max_fps_index = idx
	Game.apply_max_fps()
	Game.save_config()
	max_fps_value.text = _max_fps_text(idx)

func _max_fps_text(idx: int) -> String:
	if idx <= 0:
		return tr("fps_unlimited")
	return str(Game.FPS_CHOICES[idx])

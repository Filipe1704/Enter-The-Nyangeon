extends SceneTree

# 独立入口，不依赖 godot_ai；请通过 run_ui_ux_checks.py 隔离存档运行。
var failures: int = 0
var checks: int = 0
var menu_presses: int = 0
var filter_presses: int = 0

class HudPlayer extends Node2D:
	var player_card: Resource

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)

func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

func _touch(index: int, pressed: bool, position: Vector2, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	event.canceled = canceled
	return event

func _capture(label: String) -> void:
	if not "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var directory := "res://.godot/ui_ux_checks"
	DirAccess.make_dir_recursive_absolute(directory)
	var result := root.get_texture().get_image().save_png(directory + "/" + label + ".png")
	_check(result == OK, "保存场景渲染截图 " + label)

func _run() -> void:
	if not "etn-ui-ux-" in OS.get_user_data_dir():
		push_error("请通过 run_ui_ux_checks.py 在独立用户目录运行")
		quit(2)
		return
	var events := root.get_node("GameEvents")
	events.menu_button.connect(func(id: String):
		if id == "ui_ux_test":
			menu_presses += 1
	)
	events.scoreboard_select.connect(func(_name: String, _type: String): filter_presses += 1)
	await _check_keyboard()
	await _check_filters()
	await _check_level_cancel()
	await _check_equipment()
	await _check_card_font()
	await _check_settings()
	await _check_hud()
	await _check_navigation()
	print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_keyboard() -> void:
	var button = load("res://ui/menu_button.tscn").instantiate()
	button.button_id = "ui_ux_test"
	root.add_child(button)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.menu_button_press(_action("ui_accept"))
	_check(menu_presses == 1, "主菜单 ui_accept 执行一次")
	button.free()
	var tab = load("res://ui/option_button.tscn").instantiate()
	tab.button_id = "ui_ux_test"
	root.add_child(tab)
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.menu_button_press(_action("ui_accept"))
	_check(menu_presses == 2, "设置页签 ui_accept 执行一次")
	tab.free()

func _check_filters() -> void:
	var button = load("res://ui/menu_box_button.tscn").instantiate()
	button.button_type = "normal_sort"
	button.button_name = "date"
	root.add_child(button)
	button.size = Vector2(200, 120)
	for delta in [Vector2(0, -30), Vector2(0, 30), Vector2(-30, 0), Vector2(30, 0)]:
		var before := filter_presses
		button.button_pressed(_touch(0, true, Vector2(80, 60)))
		button.button_pressed(_touch(0, false, Vector2(80, 60) + delta))
		_check(filter_presses == before, "筛选拖动不选择 %s" % delta)
	var before := filter_presses
	button.button_pressed(_touch(0, true, Vector2(80, 60)))
	button.button_pressed(_touch(0, false, Vector2(82, 61)))
	_check(filter_presses == before + 1, "筛选短点按只选择一次")
	before = filter_presses
	button.button_pressed(_touch(0, true, Vector2(80, 60)))
	button.button_pressed(_touch(1, false, Vector2(80, 60)))
	_check(filter_presses == before, "其它手指释放不选择")
	button.button_pressed(_touch(0, false, Vector2(80, 60), true))
	_check(filter_presses == before, "取消触摸不选择")
	button.button_pressed(_touch(0, true, Vector2(80, 60)))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(110, 60)
	button.button_pressed(drag)
	button.button_pressed(_touch(0, false, Vector2(80, 60)))
	_check(filter_presses == before, "拖走再返回原点不选择")
	button.button_pressed(_touch(0, true, Vector2(80, 60)))
	drag.position = button.get_global_transform_with_canvas() * Vector2(110, 60)
	button._input(drag)
	button.button_pressed(_touch(0, false, Vector2(80, 60)))
	_check(filter_presses == before, "滚动容器消费拖动时也不误选")
	button.button_pressed(_touch(0, true, Vector2(80, 60)))
	button._input(_touch(0, false, Vector2(80, 60)))
	await process_frame
	_check(button._touch_index == -1, "释放被消费后仍清理筛选手指状态")
	button.free()

func _check_level_cancel() -> void:
	var screen = load("res://ui/level_select.tscn").instantiate()
	root.add_child(screen)
	screen.level_menu_in()
	await create_timer(0.4).timeout
	var button = screen.level_box.get_child(0)
	button.level_selected(_action("shoot"))
	_check(not button.timer.is_stopped(), "选择难度启动入场计时")
	screen._unhandled_input(_action("pause"))
	_check(button.timer.is_stopped(), "返回立即取消入场计时")
	_check(not button.on_selected and not button.on_touch, "返回复位难度选择状态")
	# 原实现未取消，失败时也停止计时，防止测试切到战斗。
	button.timer.stop()
	screen.level_menu_in()
	await create_timer(0.4).timeout
	button.level_selected(_action("shoot"))
	_check(not button.timer.is_stopped(), "再次打开能重新选择难度")
	button.timer.stop()
	screen.free()

func _check_equipment() -> void:
	var card = load("res://ui/ability_shop_item_card.tscn").instantiate()
	card.equip_card = load("res://resources/equip/bag.tres")
	root.add_child(card)
	card.t_num = 3
	card.item_text_get()
	_check("-5%" in card.equip_text.text, "书包负百分比预览显示 -5%")
	card.free()

func _check_card_font() -> void:
	var card = load("res://ui/ability_upgrade_card.tscn").instantiate()
	root.add_child(card)
	card.name_label.text = "很长的升级名称".repeat(20)
	card.description_label.text = "用于验证长描述不会持续缩小到不可读字号。".repeat(40)
	for frame in 30:
		await process_frame
	_check(card.name_label.get_theme_font_size("font_size") >= 12, "升级卡标题字号至少 12")
	_check(card.description_label.get_theme_font_size("font_size") >= 9, "升级卡正文字号至少 9")
	var scroll: ScrollContainer = card.get_node("ContentScroll")
	_check(card.size.y <= 254, "长文案不撑高升级卡")
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "长文案可滚动查看")
	card.position = Vector2(240, 40)
	await _capture("upgrade-long-text")
	card.can_select = true
	card.on_touch = true
	card.on_select = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var chosen := [0]
	card.selected.connect(func(): chosen[0] += 1)
	card.on_gui_input(_touch(0, true, Vector2(40, 40)))
	_check(chosen[0] == 0, "已预览的卡片触摸按下不立即提交")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = card.get_global_transform_with_canvas() * Vector2(40, 80)
	card._input(drag)
	card.on_gui_input(_touch(0, false, Vector2(40, 40)))
	_check(chosen[0] == 0, "卡片滚动后释放不提交")
	card.on_gui_input(_touch(0, true, Vector2(40, 40)))
	card.on_gui_input(_touch(0, false, Vector2(41, 40)))
	_check(chosen[0] == 1, "卡片短点按释放只提交一次")
	card.set_ability_upgrade(load("res://resources/upgrades/banana_magazine.tres"))
	scroll.scroll_vertical = 0
	for frame in 5:
		await process_frame
	await _capture("upgrade-normal")
	card.free()

func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event

func _wait_for_focus(control: Control) -> void:
	# 焦点应用晚于动画信号；按帧等待状态，兼容渲染首帧延迟。
	for frame in 30:
		if root.gui_get_focus_owner() == control:
			return
		await process_frame

func _check_settings() -> void:
	var screen = load("res://ui/option.tscn").instantiate()
	root.add_child(screen)
	_check(screen.menu_box.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "关闭的设置页不接收焦点")
	screen.on_option_selected()
	await screen.animation_player.animation_finished
	await process_frame
	_check(root.gui_get_focus_owner() == screen.option_button_box.get_child(0), "设置打开后聚焦首个页签")
	root.push_input(_key(KEY_ENTER))
	var page = screen.menu_box.get_node("Game")
	await page.animation_player.animation_finished
	await process_frame
	_check(page.shown, "真实 Enter 键打开 GAME 页")
	_check(page.modulate.a > 0.9 and page.scale.x > 0.9, "GAME 页动画后内容可见")
	var game := root.get_node("Game")
	var old_shake: bool = game.shake_screen
	page.shake.grab_focus()
	root.push_input(_key(KEY_ENTER))
	_check(game.shake_screen != old_shake, "真实 Enter 键切换画面震动")
	root.push_input(_key(KEY_ENTER))
	_check(game.shake_screen == old_shake, "开关再次确认恢复原值")
	for name in ["Master", "SFX", "BGM", "VOICE"]:
		var slider: HSlider = page.get_node("%" + name)
		slider.value = 0.37
		_check(slider.value_label.text == "37%", "音量百分比同步 " + name)
	await _capture("settings-top")
	page.get_node("Scroll").scroll_vertical = 1000
	await process_frame
	await _capture("settings-audio")
	screen.out_option_selected()
	_check(screen.menu_box.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "关闭设置立即禁用内容焦点")
	await create_timer(0.3).timeout
	screen.free()

func _check_hud() -> void:
	var game := root.get_node("Game")
	var old_shake: bool = game.shake_screen
	var old_flash: int = game.hit_flash_freq
	game.shake_screen = false
	game.hit_flash_freq = 0
	var player := HudPlayer.new()
	player.player_card = load("res://resources/player/momoi.tres")
	root.add_child(player)
	var stats = load("res://script/Stats.gd").new()
	var hud = load("res://ui/game_ui.tscn").instantiate()
	hud.player = player
	hud.stats = stats
	root.add_child(hud)
	hud.hurt_anim()
	_check(hud.get_node("MarginContainer/HpValue").position == Vector2.ZERO, "关闭震动后受击数值不位移")
	_check(hud.get_node("TextureRect").position == Vector2(0, -5), "关闭震动后 HUD 贴图不位移")
	_check(hud.hp_bar.material.get_shader_parameter("flash_opacity") == 0, "关闭闪白后血条不闪白")
	await create_timer(0.15).timeout
	hud.free()
	stats.free()
	player.free()
	game.shake_screen = old_shake
	game.hit_flash_freq = old_flash

func _check_navigation() -> void:
	var menu = load("res://scenes/main/menu_screen.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.8).timeout
	menu.button_open()
	_check(root.gui_get_focus_owner() == menu.menu_button_box.get_child(0), "主菜单聚焦开始游戏")
	root.push_input(_key(KEY_ENTER))
	await create_timer(1.0).timeout
	_check(menu.player_card_box.get_child_count() > 0, "键盘开始游戏显示默认社团角色")
	if menu.player_card_box.get_child_count() > 0:
		_check(root.gui_get_focus_owner() == menu.player_card_box.get_child(0), "选角自动聚焦首张卡")
		root.push_input(_key(KEY_ENTER))
		var level_screen = menu.get_node("LevelSelect")
		await level_screen.animation_player.animation_finished
		await _wait_for_focus(level_screen.level_box.get_child(0))
		_check(level_screen.visible, "键盘确认角色进入难度页")
		_check(root.gui_get_focus_owner() == level_screen.level_box.get_child(0), "难度页自动聚焦首个难度")
		root.push_input(_key(KEY_ESCAPE))
		await create_timer(0.2).timeout
		_check(not level_screen.visible, "Esc 从难度页返回选角")
		_check(root.gui_get_focus_owner() == menu.player_card_box.get_child(0), "返回选角恢复角色焦点")
	menu.free()

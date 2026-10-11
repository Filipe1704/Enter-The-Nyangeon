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
	if "--ui-ux-character-focus-only" in OS.get_cmdline_user_args():
		await _check_character_focus()
		await _check_character_focus_pointer()
		await _check_character_preview_input()
		print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1 if failures else 0)
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
	await _check_character_focus()
	await _check_character_focus_pointer()
	await _check_character_preview_input()
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
	var data := root.get_node("PlayerData")
	var original_characters: Array = data.character
	var original_groups: Array = data.group
	data.character = original_characters.duplicate()
	for card in load("res://resources/player/all_player.tres").player_group:
		if not data.character.has(card.id):
			data.character.append(card.id)
	data.group = ["GDD", "ED", "HSD", "FTF", "JTF", "DC"]
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
		_tap_key(KEY_RIGHT)
		_check(root.gui_get_focus_owner() == menu.player_card_box.get_child(1), "左右键保留角色焦点导航")
		_tap_key(KEY_DOWN)
		_tap_key(KEY_DOWN)
		var repeat := _key(KEY_DOWN)
		repeat.echo = true
		root.push_input(repeat)
		await create_timer(0.7).timeout
		_check(menu.society_card_group.back().group_id == "ED", "下键切换下一社团，快速输入及长按不重复切换")
		_check(menu.player_card_box.get_child_count() == 3 and menu.player_card_box.get_child(0).player_card.id == "utaha", "切换社团只生成该社团角色")
		_check(root.gui_get_focus_owner() == menu.player_card_box.get_child(0), "切换社团后聚焦首个角色")
		menu.society_card_box.get_child(2).hide()
		_tap_key(KEY_DOWN)
		await create_timer(0.7).timeout
		_check(menu.society_card_group.back().group_id == "FTF", "上下切换跳过隐藏社团")
		_tap_key(KEY_UP)
		await create_timer(0.7).timeout
		_check(menu.society_card_group.back().group_id == "ED", "上键切换上一社团")
		menu.society_card_box.get_child(2).show()
		_tap_key(KEY_UP)
		await create_timer(0.7).timeout
		var society_scroll: ScrollContainer = menu.society_card_box.get_parent()
		var original_scroll_height := society_scroll.size.y
		society_scroll.size.y = 150
		await process_frame
		_tap_key(KEY_UP)
		await create_timer(0.7).timeout
		_check(menu.society_card_group.back().group_id == "DC", "首社团上键循环到最后社团")
		_check(society_scroll.scroll_vertical > 0, "列表超出可视区域时自动滚动到所选社团")
		society_scroll.size.y = original_scroll_height
		society_scroll.scroll_vertical = 0
		await process_frame
		await _capture("society-keyboard-last")
		_tap_key(KEY_DOWN)
		await create_timer(0.7).timeout
		_check(menu.society_card_group.back().group_id == "GDD", "末社团下键循环到首社团")
		for society in menu.society_card_box.get_children():
			society.visible = society.group_id == "GDD"
		_tap_key(KEY_DOWN)
		_check(menu.society_card_group.back().group_id == "GDD" and not menu._society_switching, "仅一个可见社团时上下键不重建角色")
		for society in menu.society_card_box.get_children():
			society.show()
		root.push_input(_key(KEY_ENTER))
		var level_screen = menu.get_node("LevelSelect")
		await level_screen.animation_player.animation_finished
		await _wait_for_focus(level_screen.level_box.get_child(0))
		_check(level_screen.visible, "键盘确认角色进入难度页")
		_check(root.gui_get_focus_owner() == level_screen.level_box.get_child(0), "难度页自动聚焦首个难度")
		_tap_key(KEY_DOWN)
		_check(menu.society_card_group.back().group_id == "GDD", "难度页上下键不切换背后的社团")
		root.push_input(_key(KEY_ESCAPE))
		await create_timer(0.2).timeout
		_check(not level_screen.visible, "Esc 从难度页返回选角")
		_check(root.gui_get_focus_owner() == menu.player_card_box.get_child(0), "返回选角恢复角色焦点")
		_tap_key(KEY_DOWN)
		_tap_key(KEY_ESCAPE)
		await create_timer(0.7).timeout
		_check(not menu.on_select_player and menu.player_card_box.get_child_count() == 0 and not menu._society_switching, "社团切换中返回不会残留角色或切换锁")
		menu.menu_button_press("new_game")
		await create_timer(0.9).timeout
		_check(menu.society_card_group.size() == 1 and menu.society_card_group.back().group_id == "GDD" and menu.player_card_box.get_child_count() == 4, "中途返回后重新选角恢复默认社团且无混入角色")
	menu.free()
	data.character = original_characters
	data.group = original_groups


func _tap_key(keycode: Key) -> void:
	root.push_input(_key(keycode))
	var release := _key(keycode)
	release.pressed = false
	root.push_input(release)


func _check_character_focus() -> void:
	var data := root.get_node("PlayerData")
	var original_characters: Array = data.character
	var original_groups: Array = data.group
	data.character = ["momoi", "midori", "yuzu", "aris", "aris_armed"]
	data.group = ["GDD"]
	var menu = load("res://scenes/main/menu_screen.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.8).timeout
	_tap_key(KEY_ENTER)
	for frame in 180:
		if not menu._society_switching and menu.player_card_box.get_child_count() == 4 and root.gui_get_focus_owner() == menu.player_card_box.get_child(0):
			break
		await create_timer(0.005).timeout
	# 社团刚填完时，末张卡的入场动画仍可能尚未结束。
	for index in 3:
		_tap_key(KEY_RIGHT)
	await create_timer(0.2).timeout
	var focused := root.gui_get_focus_owner()
	_check(focused == menu.player_card_box.get_child(3), "快速三次右键聚焦末张角色卡")
	_check(menu.player_card_box.get_child(3).mouse_filter != Control.MOUSE_FILTER_IGNORE, "快速导航不会让末张角色卡永久禁用输入")
	_tap_key(KEY_ENTER)
	await create_timer(0.9).timeout
	_check(menu.get_node("LevelSelect").visible, "连续左右切换后 Enter 仍能确认角色并进入难度页")
	_tap_key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	# 重放真实日志：爱丽丝预览完成 → 左到柚子 → 退场动画中立即右返。
	# 此时分支按钮还可见，自动几何导航曾误入该按钮，随后隐藏导致焦点为 null。
	var reversal_stayed := true
	for delay in [0.016, 0.033, 0.05, 0.067, 0.083]:
		menu.player_card_box.get_child(3).grab_focus()
		await create_timer(0.2).timeout
		_tap_key(KEY_LEFT)
		await create_timer(delay).timeout
		_tap_key(KEY_RIGHT)
		reversal_stayed = reversal_stayed and root.gui_get_focus_owner() == menu.player_card_box.get_child(3)
		await create_timer(0.2).timeout
		reversal_stayed = reversal_stayed and root.gui_get_focus_owner() == menu.player_card_box.get_child(3)
	_check(reversal_stayed, "爱丽丝退场动画中左右折返不会误入分支按钮或丢失焦点")
	_tap_key(KEY_ENTER)
	await create_timer(0.9).timeout
	_check(menu.get_node("LevelSelect").visible, "动画中连续左右折返后 Enter 仍能确认角色")
	if menu.get_node("LevelSelect").visible:
		_tap_key(KEY_ESCAPE)
		await create_timer(0.2).timeout
	else:
		menu.player_card_box.get_child(3).grab_focus()
	var stayed_on_cards := true
	for index in 48:
		var event := _key(KEY_RIGHT if index < 24 else KEY_LEFT)
		event.echo = index % 4 == 3
		root.push_input(event)
		var release := _key(event.keycode)
		release.pressed = false
		root.push_input(release)
		await process_frame
		var owner := root.gui_get_focus_owner()
		stayed_on_cards = stayed_on_cards and owner != null and owner.get_parent() == menu.player_card_box
		await create_timer(0.015).timeout
	_check(stayed_on_cards, "48 次连续左右及重复按键不丢失角色焦点")
	_tap_key(KEY_LEFT)
	_check(root.gui_get_focus_owner() == menu.player_card_box.get_child(0), "首张角色卡向左保持焦点")
	for index in 3:
		_tap_key(KEY_RIGHT)
	var aris = menu.player_card_box.get_child(3)
	_tap_key(KEY_RIGHT)
	_check(root.gui_get_focus_owner() == aris, "末张角色卡向右保持焦点")
	await create_timer(0.2).timeout
	_tap_key(KEY_TAB)
	await create_timer(0.2).timeout
	_check(root.gui_get_focus_owner() == aris.branch_button and aris.branch_button.is_visible_in_tree(), "Tab 可进入形态切换按钮且预览保持展开")
	var previous_branch: int = aris.branch_index
	_tap_key(KEY_ENTER)
	await create_timer(0.4).timeout
	_check(aris.branch_index != previous_branch and root.gui_get_focus_owner() == aris, "Enter 切换形态并将焦点交还角色卡")
	aris.branch_button.pressed.emit()
	_tap_key(KEY_LEFT)
	_tap_key(KEY_RIGHT)
	await create_timer(0.4).timeout
	_check(not aris._switching and aris.mouse_filter != Control.MOUSE_FILTER_IGNORE, "分支动画期间左右切换不会残留输入锁")
	_tap_key(KEY_ENTER)
	await create_timer(0.9).timeout
	_check(menu.get_node("LevelSelect").visible, "连续导航及分支切换后键盘仍可确认角色")
	_tap_key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	aris.branch_button.pressed.emit()
	_tap_key(KEY_LEFT)
	_tap_key(KEY_ENTER)
	await create_timer(0.9).timeout
	_check(menu.get_node("LevelSelect").visible and not aris._switching and aris.mouse_filter == Control.MOUSE_FILTER_IGNORE, "其他角色确认后分支动画完成不会重新启用背景卡片")
	menu.free()
	data.character = original_characters
	data.group = original_groups


func _check_character_focus_pointer() -> void:
	if not "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		return
	var data := root.get_node("PlayerData")
	var original_characters: Array = data.character
	var original_groups: Array = data.group
	data.character = ["momoi", "midori", "yuzu", "aris", "aris_armed"]
	data.group = ["GDD"]
	var menu = load("res://scenes/main/menu_screen.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.8).timeout
	menu.menu_button_press("new_game")
	await create_timer(0.8).timeout
	for pointer_index in 4:
		var card: Control = menu.player_card_box.get_child(pointer_index)
		var motion := InputEventMouseMotion.new()
		motion.position = card.get_global_rect().get_center()
		root.push_input(motion, true)
		root.warp_mouse(motion.position)
		await create_timer(0.1).timeout
		_check(card.get_global_mouse_position().distance_to(motion.position) < 2, "渲染窗口鼠标确实停在目标角色 %s" % pointer_index)
		var stayed := true
		for index in 64:
			var key := _key(KEY_RIGHT if index % 16 < 8 else KEY_LEFT)
			key.echo = index % 3 == 2
			Input.parse_input_event(key)
			Input.flush_buffered_events()
			await create_timer(0.025).timeout
			var release := _key(key.keycode)
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			await create_timer(0.007).timeout
			var focused := root.gui_get_focus_owner()
			if focused == null or focused.get_parent() != menu.player_card_box:
				stayed = false
		_check(stayed, "鼠标停在角色 %s 时连续左右键不丢失焦点" % pointer_index)
		_tap_key(KEY_ENTER)
		await create_timer(0.8).timeout
		_check(menu.get_node("LevelSelect").visible, "鼠标悬停期间连续左右键后仍可确认 %s" % pointer_index)
		if not menu.get_node("LevelSelect").visible:
			await _capture("character-focus-pointer-failed")
			break
		_tap_key(KEY_ESCAPE)
		await create_timer(0.2).timeout
	menu.free()
	data.character = original_characters
	data.group = original_groups


func _check_character_preview_input() -> void:
	if not "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		return
	var data := root.get_node("PlayerData")
	var original_characters: Array = data.character
	var original_groups: Array = data.group
	data.character = ["momoi", "midori", "yuzu", "aris", "aris_armed"]
	data.group = ["GDD"]
	var menu = load("res://scenes/main/menu_screen.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.8).timeout
	menu.menu_button_press("new_game")
	await create_timer(0.8).timeout
	root.warp_mouse(Vector2(630, 350))
	await create_timer(0.2).timeout
	_tap_key(KEY_RIGHT)
	_tap_key(KEY_RIGHT)
	await create_timer(0.2).timeout
	var midori: Control = menu.player_card_box.get_child(1)
	var yuzu: Control = menu.player_card_box.get_child(2)
	var motion := InputEventMouseMotion.new()
	motion.position = midori.get_global_rect().get_center()
	motion.relative = Vector2(1, 0)
	root.warp_mouse(motion.position)
	root.push_input(motion, true)
	await create_timer(0.2).timeout
	_check(midori.get_global_mouse_position().distance_to(motion.position) < 2, "混合输入检查的鼠标确实位于绿子卡片")
	_check(root.gui_get_focus_owner() == midori and midori.color_rect.visible and not yuzu.color_rect.visible, "鼠标移动到另一角色时焦点与唯一预览同步")
	# 鼠标继续停在绿子，键盘返回柚子；静止指针不得维持第二张预览。
	midori.grab_focus()
	_tap_key(KEY_RIGHT)
	await create_timer(0.2).timeout
	_check(root.gui_get_focus_owner() == yuzu and yuzu.color_rect.visible and not midori.color_rect.visible, "键盘切换后静止鼠标不展开另一张角色卡")
	# 无实际位移的鼠标事件不能抢回键盘焦点。
	motion.relative = Vector2.ZERO
	root.push_input(motion, true)
	await create_timer(0.2).timeout
	_check(root.gui_get_focus_owner() == yuzu, "零位移鼠标事件不抢回键盘角色焦点")
	_tap_key(KEY_ENTER)
	await create_timer(0.9).timeout
	_check(menu.get_node("LevelSelect").visible and menu.get_node("LevelSelect").player == yuzu.player, "混合输入后 Enter 确认当前唯一预览角色")
	menu.free()
	data.character = original_characters
	data.group = original_groups

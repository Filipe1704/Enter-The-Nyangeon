extends SceneTree

# 独立入口，不依赖 godot_ai；请通过 run_ui_ux_checks.py 隔离存档运行。
var failures: int = 0
var checks: int = 0
var menu_presses: int = 0
var filter_presses: int = 0

class HudPlayer extends Node2D:
	var player_card: Resource

class TestUpgradeReceiver extends Node:
	var applied: int = 0
	func apply_upgrade(_upgrade: AbilityUpgrade) -> void:
		applied += 1

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
	if "--ui-ux-test-item-input-only" in OS.get_cmdline_user_args():
		await _check_test_item_mouse()
		print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1 if failures else 0)
		return
	if "--ui-ux-level-focus-only" in OS.get_cmdline_user_args():
		await _check_level_entry_visuals()
		await _check_level_keyboard_regions()
		print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1 if failures else 0)
		return
	if "--ui-ux-scroll-input-only" in OS.get_cmdline_user_args():
		await _check_scroll_mouse_state()
		print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1 if failures else 0)
		return
	if "--ui-ux-main-menu-focus-only" in OS.get_cmdline_user_args():
		await _check_main_menu_focus()
		await _check_main_menu_order()
		print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1 if failures else 0)
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
	await _check_main_menu_focus()
	await _check_main_menu_order()
	await _check_character_focus()
	await _check_character_focus_pointer()
	await _check_character_preview_input()
	await _check_test_item_mouse()
	await _check_scroll_mouse_state()
	await _check_level_entry_visuals()
	await _check_level_keyboard_regions()
	print("UI_UX_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_level_entry_visuals() -> void:
	var screen = load("res://ui/level_select.tscn").instantiate()
	root.add_child(screen)
	root.warp_mouse(Vector2(20, 20))
	for opening in 2:
		root.get_node("GameEvents").emit_level_select_in()
		var flashed: Array[String] = await _observe_level_entry(screen)
		_check(flashed.is_empty(), "第 %d 次进入难度页时未聚焦按钮不闪亮：%s" % [opening + 1, str(flashed)])
		_check(root.gui_get_focus_owner() == screen.level_box.get_child(0), "入场完成后仍只聚焦 NORMAL")
		_tap_key(KEY_DOWN)
		await create_timer(0.15).timeout
		_tap_key(KEY_ESCAPE)
		await screen.animation_player.animation_finished
	screen.free()

func _observe_level_entry(screen: CanvasLayer) -> Array[String]:
	var flashed: Array[String] = []
	var start := Time.get_ticks_msec()
	var settled_at := -1
	while Time.get_ticks_msec() - start < 4000:
		await process_frame
		if screen._keyboard_ready and settled_at < 0:
			settled_at = Time.get_ticks_msec()
		if not screen.visible:
			continue
		# 全程观察入场；只检查动画结束后的最终状态会漏掉短暂亮起。
		for button in screen.level_box.get_children().slice(1):
			var shade: ColorRect = button.get_node("Node2D/LevelColor/BlackColor")
			if shade.color.a < 0.6 and not flashed.has(button.name):
				flashed.append(button.name)
		if settled_at >= 0 and Time.get_ticks_msec() - settled_at >= 150:
			break
	return flashed

func _level_tab(reverse: bool = false) -> void:
	var press := _key(KEY_TAB)
	press.shift_pressed = reverse
	root.push_input(press)
	press = _key(KEY_TAB)
	press.shift_pressed = reverse
	press.pressed = false
	root.push_input(press)

func _check_level_keyboard_regions() -> void:
	var support_data := root.get_node("SupportData")
	var player_data := root.get_node("PlayerData")
	var old_supports: Dictionary = support_data.support_data.duplicate()
	var old_support: SupportCard = support_data.game_support
	var old_modes: Array = player_data.game_mode.duplicate()
	support_data.support_data = {}
	support_data.add_new_data(load("res://resources/support/kei.tres"))
	support_data.game_support = support_data.null_support
	player_data.game_mode = []
	var screen = load("res://ui/level_select.tscn").instantiate()
	var mode_panel = screen.get_node("Node2D2/gamemode_button")
	mode_panel.gamemode_card = mode_panel.gamemode_card.duplicate()
	mode_panel.gamemode_card.append(load("res://resources/game_mode/hujiu_mode.tres"))
	root.add_child(screen)
	root.warp_mouse(Vector2(630, 350))
	root.get_node("GameEvents").emit_level_select_in()
	await screen.animation_player.animation_finished
	await process_frame
	var support = screen.get_node("Node2D2/support_ui")
	var modes: Array = screen.get_node("Node2D2/gamemode_button/MarginContainer/ScrollContainer/GridContainer").get_children()
	var back: Button = screen.get_node("Node2D2/return")
	_check(root.gui_get_focus_owner() == screen.level_box.get_child(0), "难度页打开仍聚焦 NORMAL")
	_level_tab()
	_check(root.gui_get_focus_owner() == modes[0], "Tab 从难度区域进入模式区域")
	_check(modes[0].text_show.visible, "键盘聚焦模式时显示说明")
	if "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		_item_mouse_motion(modes[1].get_global_rect().get_center(), Vector2(10, 0), 0)
		_check(root.gui_get_focus_owner() == modes[1], "鼠标实际移动进入另一模式时接管焦点")
		_tap_key(KEY_LEFT)
		_item_mouse_motion(modes[1].get_global_rect().get_center(), Vector2.ZERO, 0)
		_check(root.gui_get_focus_owner() == modes[0], "静止鼠标不抢回键盘模式焦点")
	await create_timer(0.15).timeout
	await _capture("level-mode-keyboard")
	_tap_key(KEY_ENTER)
	var echo := _key(KEY_ENTER)
	echo.echo = true
	root.push_input(echo)
	_tap_key(KEY_ENTER)
	_check(player_data.game_mode.has(modes[0].game_mode), "按键重复及动画期间重复确认不反复切换模式")
	await create_timer(0.6).timeout
	_check(player_data.game_mode.has(modes[0].game_mode), "Enter 开启聚焦模式")
	_tap_key(KEY_SPACE)
	await create_timer(0.6).timeout
	_check(not player_data.game_mode.has(modes[0].game_mode), "Space 关闭聚焦模式")
	_tap_key(KEY_RIGHT)
	_check(root.gui_get_focus_owner() == modes[1], "左右键在模式区域内移动")
	_tap_key(KEY_ENTER)
	_tap_key(KEY_LEFT)
	_tap_key(KEY_ENTER)
	await create_timer(0.6).timeout
	_check(player_data.game_mode.has(modes[0].game_mode) and player_data.game_mode.has(modes[1].game_mode), "闪击与无尽模式仍可同时开启")
	_tap_key(KEY_RIGHT)
	_tap_key(KEY_RIGHT)
	_tap_key(KEY_ENTER)
	_tap_key(KEY_LEFT)
	await create_timer(0.6).timeout
	_check(player_data.game_mode == ["hujiu"] and not modes[0].on_selected and not modes[1].on_selected, "键盘启用扩展模式时保留互斥规则，动画中移动焦点不打断切换")
	_level_tab()
	_check(root.gui_get_focus_owner() == back, "Tab 从模式区域进入返回按钮")
	_level_tab(true)
	_check(root.gui_get_focus_owner() == modes[1], "Shift+Tab 返回模式区域并记住原位置")
	_level_tab()
	_level_tab()
	_check(root.gui_get_focus_owner() == support.main_card, "Tab 从返回按钮循环到支援区域")
	_tap_key(KEY_ENTER)
	await create_timer(0.2).timeout
	_check(support.margin_container.visible and root.gui_get_focus_owner() == support.support_box.get_child(0), "Enter 展开支援列表并聚焦当前支援")
	_tap_key(KEY_DOWN)
	_check(root.gui_get_focus_owner() == support.support_box.get_child(1), "上下键选择支援项目")
	_check(support_data.game_support.support_id == "null", "仅浏览支援不立即应用")
	await create_timer(0.15).timeout
	await _capture("level-support-keyboard")
	_tap_key(KEY_ENTER)
	await create_timer(0.5).timeout
	_check(support_data.game_support.support_id == "kei", "Enter 应用支援选择")
	_check(not support.margin_container.visible and root.gui_get_focus_owner() == support.main_card, "选择支援后收起列表并返回支援主卡")
	_tap_key(KEY_ENTER)
	await create_timer(0.2).timeout
	_check(root.gui_get_focus_owner() == support.support_box.get_child(1), "重新展开时聚焦已选支援")
	_tap_key(KEY_ESCAPE)
	await support.ui_anim.animation_finished
	_check(screen.visible and not support.margin_container.visible and root.gui_get_focus_owner() == support.main_card, "Esc 优先收起支援列表而不退出难度页")
	_tap_key(KEY_ENTER)
	_level_tab()
	await create_timer(0.2).timeout
	_check(root.gui_get_focus_owner() == screen.level_box.get_child(0), "支援展开中 Tab 离开后延迟回调不抢回焦点")
	_tap_key(KEY_DOWN)
	_check(root.gui_get_focus_owner() == screen.level_box.get_child(1), "上下键选择难度")
	if "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		_item_mouse_motion(screen.level_box.get_child(2).get_global_rect().get_center(), Vector2(0, 10), 0)
		_check(root.gui_get_focus_owner() == screen.level_box.get_child(2), "鼠标进入难度按钮后 Enter 与焦点一致")
	_level_tab()
	_level_tab()
	_tap_key(KEY_ENTER)
	await screen.animation_player.animation_finished
	_check(not screen.visible, "返回按钮 Enter 返回选角页")
	_check(support.main_card.focus_mode == Control.FOCUS_NONE and modes[0].focus_mode == Control.FOCUS_NONE, "关闭页面后辅助区域不接收焦点")
	root.get_node("GameEvents").emit_level_select_in()
	await screen.animation_player.animation_finished
	await process_frame
	_level_tab()
	_tap_key(KEY_ENTER)
	_level_tab(true)
	_tap_key(KEY_ENTER)
	var difficulty = screen.level_box.get_child(0)
	_check(not difficulty.timer.is_stopped(), "难度 Enter 仍启动入场计时")
	_check(support.main_card.focus_mode == Control.FOCUS_NONE and back.disabled, "确认难度后锁定支援、模式和返回按钮")
	support.open_list()
	_check(not support.list_open and support.main_card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "确认难度后鼠标也不能重新打开支援列表")
	_level_tab()
	await create_timer(0.3).timeout
	_check(modes[0].mouse_filter == Control.MOUSE_FILTER_IGNORE, "模式动画结束不会重新启用已锁定页面")
	_tap_key(KEY_ESCAPE)
	await process_frame
	_check(difficulty.timer.is_stopped(), "Esc 返回仍取消难度入场计时")
	screen.free()
	support_data.support_data = old_supports
	support_data.game_support = old_support
	player_data.game_mode = old_modes
	if old_support != null:
		support_data.get_card(old_support)

func _item_mouse_button(position: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)

func _item_mouse_motion(position: Vector2, relative: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = mask
	root.push_input(event, true)

func _check_scroll_mouse_state() -> void:
	if not "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		return
	var scroll := ScrollContainer.new()
	scroll.set_script(load("res://script/ScrollBox.gd"))
	scroll.position = Vector2(30, 30)
	scroll.size = Vector2(190, 130)
	root.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(160, 800)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)
	await process_frame
	await process_frame
	var point := Vector2(80, 100)
	root.warp_mouse(point)
	await create_timer(0.1).timeout
	scroll.scroll_vertical = 200
	_item_mouse_motion(point + Vector2(0, -10), Vector2(0, -10), 0)
	_check(scroll.scroll_vertical == 200, "未按鼠标时移动指针不滚动列表")
	_item_mouse_button(point, true, MOUSE_BUTTON_WHEEL_DOWN)
	var after_wheel: int = scroll.scroll_vertical
	_check(after_wheel > 200, "滚轮仍按原生方式滚动列表")
	_check(not scroll.isDrag, "滚轮事件不进入列表拖动状态")
	_item_mouse_motion(point + Vector2(0, -20), Vector2(0, -20), 0)
	_check(scroll.scroll_vertical == after_wheel, "滚轮操作后仅移动鼠标不再带动角色列表")
	_item_mouse_button(point, false, MOUSE_BUTTON_WHEEL_DOWN)
	_item_mouse_button(point, true, MOUSE_BUTTON_RIGHT)
	var before: int = scroll.scroll_vertical
	_item_mouse_motion(point + Vector2(0, -20), Vector2(0, -20), MOUSE_BUTTON_MASK_RIGHT)
	_check(not scroll.isDrag and scroll.scroll_vertical == before, "右键按住移动不启动列表拖动")
	_item_mouse_button(point, false, MOUSE_BUTTON_RIGHT)
	_item_mouse_button(point, true)
	before = scroll.scroll_vertical
	_item_mouse_motion(point + Vector2(0, -20), Vector2(0, -20))
	_check(scroll.scroll_vertical == before + 20, "左键按住移动仍可正常拖动列表")
	_item_mouse_button(point + Vector2(0, -20), false)
	before = scroll.scroll_vertical
	_item_mouse_motion(point, Vector2(0, 20), 0)
	_check(not scroll.isDrag and scroll.scroll_vertical == before, "松开左键后鼠标移动不继续拖动")
	_item_mouse_button(point, true)
	before = scroll.scroll_vertical
	_item_mouse_motion(point + Vector2(0, -20), Vector2(0, -20), 0)
	_check(not scroll.isDrag and scroll.scroll_vertical == before, "移动事件显示左键已松开时清理遗漏的释放状态")
	_item_mouse_button(point, true)
	_item_mouse_button(Vector2(300, 250), false)
	_check(not scroll.isDrag, "在列表外松开左键也结束拖动")
	_item_mouse_button(point, true)
	scroll.hide()
	scroll.show()
	_check(not scroll.isDrag, "关闭并重新显示列表不保留拖动状态")
	_item_mouse_button(point, false)
	_item_mouse_button(point, true)
	scroll.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not scroll.isDrag, "窗口失焦会取消列表拖动")
	_item_mouse_button(point, false)
	root.push_input(_touch(3, true, point), true)
	before = scroll.scroll_vertical
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = point + Vector2(0, -20)
	drag.relative = Vector2(0, -20)
	root.push_input(drag, true)
	_check(scroll.scroll_vertical > before, "触屏仍可拖动列表")
	root.push_input(_touch(4, true, point), true)
	root.push_input(_touch(4, false, point), true)
	_check(scroll.isDrag, "其它手指的释放不会中断当前触屏拖动")
	root.push_input(_touch(3, false, Vector2(300, 250), true), true)
	_check(not scroll.isDrag, "当前触点在列表外取消也结束拖动")
	scroll.free()

func _check_test_item_mouse() -> void:
	if not "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		return
	# 复用测试房的真实 ScrollBox 和道具卡，替换的仅是道具效果接收器。
	var receiver := TestUpgradeReceiver.new()
	root.add_child(receiver)
	var scroll := ScrollContainer.new()
	scroll.set_script(load("res://script/ScrollBox.gd"))
	scroll.position = Vector2(30, 30)
	scroll.size = Vector2(190, 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)
	var upgrade := AbilityUpgrade.new()
	upgrade.id = "ui_test_drag"
	upgrade.order_num = 10
	for index in 24:
		var card = load("res://ui/test_item_card.tscn").instantiate()
		card.custom_minimum_size = Vector2(40, 40)
		grid.add_child(card)
		card.upgrade_manager = receiver
		card.get_card(upgrade)
	await process_frame
	await process_frame
	scroll.scroll_vertical = 40
	await process_frame
	var card = grid.get_child(8)
	var start: Vector2 = card.button.get_global_transform_with_canvas() * (card.button.size / 2)
	var before_scroll: int = scroll.scroll_vertical
	root.warp_mouse(start)
	await create_timer(0.1).timeout
	_item_mouse_button(start, true)
	_check(receiver.applied == 0, "道具鼠标按下不立即发放，等待区分点击与拖动")
	_item_mouse_motion(start + Vector2(0, -34), Vector2(0, -34))
	await process_frame
	_item_mouse_button(start + Vector2(0, -34), false)
	await process_frame
	_check(scroll.scroll_vertical > before_scroll, "从道具卡开始的鼠标拖动仍能滚动列表")
	_check(receiver.applied == 0 and card.num == 10, "鼠标拖动道具列表不发放道具或消耗次数")
	var point: Vector2 = card.button.get_global_transform_with_canvas() * (card.button.size / 2)
	var before: int = receiver.applied
	_item_mouse_button(point, true)
	_item_mouse_button(point, false)
	await process_frame
	_check(receiver.applied == before + 1, "鼠标普通点击道具恰好生效一次")
	before = receiver.applied
	_item_mouse_button(point, true, MOUSE_BUTTON_RIGHT)
	_item_mouse_button(point, false, MOUSE_BUTTON_RIGHT)
	await process_frame
	_check(receiver.applied == before, "鼠标右键不发放道具")
	# 按住时滚出再移回，结束点相同也属于拖动。
	scroll.scroll_vertical = 40
	await process_frame
	point = card.button.get_global_transform_with_canvas() * (card.button.size / 2)
	before = receiver.applied
	_item_mouse_button(point, true)
	_item_mouse_motion(point + Vector2(0, -30), Vector2(0, -30))
	_item_mouse_motion(point, Vector2(0, 30))
	_item_mouse_button(point, false)
	await process_frame
	_check(receiver.applied == before, "拖动后移回原点松手仍不发放道具")
	# 小幅抖动仍视为普通点击。
	point = card.button.get_global_transform_with_canvas() * (card.button.size / 2)
	_item_mouse_button(point, true)
	_item_mouse_motion(point + Vector2(2, 2), Vector2(2, 2))
	_item_mouse_button(point + Vector2(2, 2), false)
	await process_frame
	_check(receiver.applied == before + 1, "鼠标点击的小幅抖动仍可发放道具")
	before = receiver.applied
	point = card.button.get_global_transform_with_canvas() * (card.button.size / 2)
	_item_mouse_button(point, true)
	_item_mouse_motion(Vector2(300, 250), Vector2(300, 250) - point)
	_item_mouse_button(Vector2(300, 250), false)
	await process_frame
	_check(receiver.applied == before and not card._mouse_pressed, "列表外松手不发放道具且清理按压状态")
	scroll.scroll_vertical = 40
	await process_frame
	point = card.button.get_global_transform_with_canvas() * (card.button.size / 2)
	_item_mouse_button(point, false)
	await process_frame
	_check(receiver.applied == before, "没有对应按下的释放不发放道具")
	_item_mouse_button(point, true)
	card.close_button()
	_item_mouse_button(point, false)
	await process_frame
	card.open_button()
	_check(receiver.applied == before and not card._mouse_pressed, "按住期间禁用卡片会取消待确认点击")
	# 前一次释放的延迟清理不得取消紧随其后的下一次按下。
	_item_mouse_button(point, true)
	_item_mouse_button(point, false)
	_item_mouse_button(point, true)
	await process_frame
	_check(receiver.applied == before + 1 and card._mouse_pressed, "快速连续点击不会被前次延迟清理打断")
	_item_mouse_button(point, false)
	await process_frame
	_check(receiver.applied == before + 2, "快速连续点击每次释放只发放一次")
	before = receiver.applied
	root.push_input(_touch(0, true, point), true)
	root.push_input(_touch(0, false, point), true)
	await process_frame
	_check(receiver.applied == before and card.on_touch, "触屏第一次点按仍只预览道具")
	root.push_input(_touch(0, true, point), true)
	root.push_input(_touch(0, false, point), true)
	await process_frame
	_check(receiver.applied == before + 1, "触屏第二次点按仍发放道具一次")
	scroll.free()
	receiver.free()

func _main_menu_highlights(menu: Node) -> Array:
	var highlighted: Array = []
	for button in menu.menu_button_box.get_children():
		if button.get_node("Node2D/ColorRect").size.x > 4:
			highlighted.append(button)
	return highlighted

func _move_main_menu_pointer(position: Vector2, relative: Vector2 = Vector2.ONE) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.relative = relative
	# 零位移检查只注入该事件，避免 warp 额外产生系统鼠标位移干扰结论。
	if relative != Vector2.ZERO:
		root.warp_mouse(position)
	root.push_input(motion, true)
	await create_timer(0.12).timeout

func _check_main_menu_focus() -> void:
	if not "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		return
	var menu = load("res://scenes/main/menu_screen.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.8).timeout
	await _move_main_menu_pointer(Vector2(630, 350))
	var buttons: Array = menu.menu_button_box.get_children()
	# 保留真实场景与信号路径，用无副作用的按钮 id 记录确认项，避免进入战斗或退出测试。
	for index in buttons.size():
		buttons[index].button_id = "ui_focus_%d" % index
	var confirmed: Array[String] = []
	var record := func(id: String): confirmed.append(id)
	var events := root.get_node("GameEvents")
	events.menu_button.connect(record)
	buttons[0].grab_focus()
	await create_timer(0.12).timeout
	_check(_main_menu_highlights(menu) == [buttons[0]], "主菜单初始仅键盘焦点项高亮")
	var target: Vector2 = buttons[1].get_global_rect().get_center()
	await _move_main_menu_pointer(target)
	_check(root.gui_get_focus_owner() == buttons[1], "真实鼠标移动到主菜单另一项时同步键盘焦点")
	_check(_main_menu_highlights(menu) == [buttons[1]], "鼠标接管后主菜单只高亮一项")
	_tap_key(KEY_ENTER)
	_check(confirmed == ["ui_focus_1"], "Enter 仅确认鼠标刚选中的主菜单项一次")
	buttons[1].grab_focus()
	_tap_key(KEY_DOWN)
	await create_timer(0.12).timeout
	_check(root.gui_get_focus_owner() == buttons[2] and _main_menu_highlights(menu) == [buttons[2]], "主菜单键盘切换后静止鼠标不保留第二项高亮")
	await _move_main_menu_pointer(target, Vector2.ZERO)
	_check(root.gui_get_focus_owner() == buttons[2], "主菜单零位移鼠标事件不抢回键盘焦点")
	await _move_main_menu_pointer(target + Vector2(1, 0))
	_check(root.gui_get_focus_owner() == buttons[1] and _main_menu_highlights(menu) == [buttons[1]], "指针未离开按钮时重新移动也能接管键盘选择")
	await _move_main_menu_pointer(Vector2(630, 350))
	_check(root.gui_get_focus_owner() == buttons[1] and _main_menu_highlights(menu) == [buttons[1]], "鼠标离开主菜单按钮后保留唯一键盘选择")
	menu.button_close()
	await _move_main_menu_pointer(buttons[0].get_global_rect().get_center())
	_check(not buttons.has(root.gui_get_focus_owner()) and _main_menu_highlights(menu).is_empty(), "主菜单禁用期间鼠标不会夺取焦点或重新高亮")
	menu.button_open()
	var before := confirmed.size()
	buttons[1].menu_button_press(_touch(0, true, Vector2(20, 10)))
	await create_timer(0.12).timeout
	_check(confirmed.size() == before and root.gui_get_focus_owner() == buttons[1] and _main_menu_highlights(menu) == [buttons[1]], "主菜单触摸首次点按仅预览且共用唯一焦点")
	buttons[1].menu_button_press(_touch(0, true, Vector2(20, 10)))
	_check(confirmed.size() == before + 1 and confirmed.back() == "ui_focus_1", "主菜单触摸第二次点按只确认当前项一次")
	events.menu_button.disconnect(record)
	menu.free()

func _check_main_menu_vertical_path(menu: Node, label: String) -> void:
	menu.button_open()
	await create_timer(0.12).timeout
	var buttons: Array[Control] = []
	for child in menu.menu_button_box.get_children():
		if child is Control and child.is_visible_in_tree() and not child.is_queued_for_deletion():
			buttons.append(child)
	var forward := true
	for index in buttons.size() - 1:
		buttons[index].grab_focus()
		_tap_key(KEY_DOWN)
		forward = forward and root.gui_get_focus_owner() == buttons[index + 1]
	_check(forward, label + "：下键按可见菜单顺序导航")
	var backward := true
	for index in range(1, buttons.size()):
		buttons[index].grab_focus()
		_tap_key(KEY_UP)
		backward = backward and root.gui_get_focus_owner() == buttons[index - 1]
	_check(backward, label + "：上键按可见菜单顺序导航")
	buttons[0].grab_focus()
	_tap_key(KEY_UP)
	_check(root.gui_get_focus_owner() == buttons[0], label + "：首项上键停留在首项")
	buttons.back().grab_focus()
	var stayed_at_end := true
	for repeat in 3:
		_tap_key(KEY_DOWN)
		stayed_at_end = stayed_at_end and root.gui_get_focus_owner() == buttons.back()
	_check(stayed_at_end, label + "：QUIT 每次下键都停留在末项，不跳回 OPTION")

func _check_main_menu_order() -> void:
	var menu = load("res://scenes/main/menu_screen.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.8).timeout
	if "--ui-ux-screenshots" in OS.get_cmdline_user_args():
		await _move_main_menu_pointer(Vector2(630, 350))
	await _check_main_menu_vertical_path(menu, "当前已加载的主菜单")
	# 模拟更多 MOD 在 QUIT 前插入共用场景；该场景继承了旧的固定邻居。
	var quit_button: Control = menu.menu_button_box.get_children().filter(func(child): return child.button_id == "game_quit")[0]
	var injected = load("res://ui/menu_button.tscn").instantiate()
	injected.button_id = "ui_order_test"
	menu.menu_button_box.add_child(injected)
	menu.menu_button_box.move_child(injected, quit_button.get_index())
	await _check_main_menu_vertical_path(menu, "新增 MOD 入口后")
	injected.hide()
	await _check_main_menu_vertical_path(menu, "隐藏 MOD 入口后")
	injected.show()
	menu.menu_button_box.move_child(injected, 1)
	await _check_main_menu_vertical_path(menu, "重排 MOD 入口后")
	menu.free()

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
	var flashed: Array[String] = await _observe_level_entry(menu.get_node("LevelSelect"))
	_check(flashed.is_empty(), "真实选角确认后未聚焦难度不闪亮：" + str(flashed))
	await create_timer(0.25).timeout
	_check(menu.get_node("LevelSelect").visible, "连续左右切换后 Enter 仍能确认角色并进入难度页")
	_level_tab()
	_level_tab()
	_tap_key(KEY_ENTER)
	await create_timer(0.2).timeout
	_check(not menu.get_node("LevelSelect").visible and not menu.on_select_level and root.gui_get_focus_owner() == menu.player_card_box.get_child(3), "难度页返回按钮 Enter 关闭覆盖层并恢复角色焦点")
	_tap_key(KEY_ENTER)
	await create_timer(0.9).timeout
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

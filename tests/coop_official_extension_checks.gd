extends SceneTree

var checks := 0
var failures := 0

class TestPage extends VBoxContainer:
	var action := Button.new()
	func _init():
		action.text = "Test action"
		action.focus_mode = Control.FOCUS_ALL
		action.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(action)
	func get_interactive_controls() -> Array[Control]:
		return [action]

class TestProvider extends Node:
	signal prepared(endpoint: Dictionary)
	signal failed(message: String)
	var menu_title := "Test network"
	var page: TestPage
	func start(_plan, _hosting): return true
	func stop(): pass
	func diagnostics(): return {"state": "idle"}
	func create_menu_page():
		page = TestPage.new()
		return page

func _initialize(): _run.call_deferred()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func _run():
	await process_frame
	var registry = get_first_node_in_group("CoopExtensionHost")
	check(registry != null, "仅官方包也提供通用接口")
	if registry == null:
		quit(1)
		return
	var session = load("res://mods/etn_coop/net/coop_net.gd").instance
	var records: Array = root.get_node("ModManager").list_mods()
	check(records.size() == 1 and records[0].id == "etn_coop", "仅安装官方联机包")
	check(registry.get_menu_pages().is_empty(), "无提供者时不添加额外页签")
	session.settings.upnp_enabled = false
	change_scene_to_file("res://scenes/main/menu_screen.tscn")
	await create_timer(0.4).timeout
	var menu_scene = load("res://mods/etn_coop/ui/coop_menu.tscn")
	var baseline_menu = menu_scene.instantiate()
	current_scene.add_child(baseline_menu)
	baseline_menu.on_coop_selected()
	await create_timer(0.3).timeout
	check(baseline_menu._extension_pages.is_empty() and baseline_menu._extension_buttons.is_empty(), "官方菜单保留原有入口")
	baseline_menu.queue_free()
	await process_frame
	var provider := TestProvider.new()
	root.add_child(provider)
	check(registry.register_backend("test_network", provider), "通用提供者注册")
	var menu = menu_scene.instantiate()
	current_scene.add_child(menu)
	menu.on_coop_selected()
	await create_timer(0.3).timeout
	check(menu._extension_pages.has("test_network"), "官方菜单创建提供者页签")
	var entry: Dictionary = menu._extension_pages["test_network"]
	check(entry.tab.get_parent() == menu.option.get_parent() and entry.tab.get_index() < menu.option.get_index(), "通用页签位于选项前")
	menu._select_extension("test_network")
	await create_timer(0.3).timeout
	check(entry.page.is_visible_in_tree() and not menu._lan_panel.visible and not menu._relay_panel.visible and not menu._option_panel.visible, "拓展页面与内置页互斥")
	check(entry.tab.on_show and not menu.lan.on_show, "页签高亮互斥")
	check(menu._get_nav_items().has(provider.page.action), "导航包含当前页面按钮")
	registry.state_changed.emit("test_network", "preparing", "")
	menu._on_connection_status_changed("offline")
	check(menu._status_label.text.contains(tr("coop_status_extension_preparing")), "旧离线通知不覆盖准备状态")
	registry.state_changed.emit("test_network", "ready", "")
	menu._on_connection_status_changed("test_connected")
	check(menu._status_label.text.contains("test_connected"), "就绪后显示游戏连接状态")
	menu._set_selected_mode(0, false)
	menu._select_extension("test_network")
	check(menu._status_label.text.contains("test_connected"), "切页保留连接结果")
	registry.state_changed.emit("test_network", "failed", "test_failure")
	menu._on_connection_status_changed("offline")
	check(menu._status_label.text.contains("test_failure"), "迟到连接通知不覆盖失败原因")
	menu.out_coop_selected()
	check(provider.page.action.focus_mode == Control.FOCUS_NONE and provider.page.action.mouse_filter == Control.MOUSE_FILTER_IGNORE, "关闭菜单撤销页面交互")
	await create_timer(0.3).timeout
	menu.on_coop_selected()
	await create_timer(0.3).timeout
	check(provider.page.action.focus_mode == Control.FOCUS_ALL and provider.page.action.mouse_filter == Control.MOUSE_FILTER_PASS, "重开恢复提供者原始交互设置")
	menu.queue_free()
	await process_frame
	check(is_instance_valid(provider) and registry.get_menu_pages().size() == 1, "释放菜单保留提供者")
	registry.unregister_backend("test_network")
	provider.queue_free()
	session.close_session()
	await process_frame
	print("OFFICIAL_EXTENSION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

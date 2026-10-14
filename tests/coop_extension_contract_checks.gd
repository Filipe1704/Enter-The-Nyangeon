extends SceneTree

const Registry := preload("res://registry.gd")
var checks := 0
var failures := 0

class Session extends Node:
	var extensions
	var is_lan_game := false
	var installed_port := 0
	var menu_returns := 0
	func is_connect_in_flight(): return false
	func close_session():
		extensions.close()
		is_lan_game = false
	func host_game(port):
		extensions.close()
		installed_port = port
		is_lan_game = true
		return true
	func join_game(_ip, port): return host_game(port)
	func return_to_menu_after_disconnect():
		menu_returns += 1
		close_session()

class Provider extends Node:
	signal prepared(endpoint: Dictionary)
	signal failed(message: String)
	var menu_title := "Test"
	var starts := 0
	var stops := 0
	var accepted := true
	func start(_plan, _hosting):
		starts += 1
		return accepted
	func stop(): stops += 1
	func diagnostics(): return {"state": "test"}
	func open_menu(): pass

class PageProvider extends Provider:
	func create_menu_page(): return Control.new()

func _initialize(): _run.call_deferred()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func _run():
	var session := Session.new()
	root.add_child(session)
	var registry = Registry.new()
	session.add_child(registry)
	registry.setup(session)
	session.extensions = registry
	var first := Provider.new()
	var second := PageProvider.new()
	root.add_child(first)
	root.add_child(second)
	check(registry.register_backend("first", first), "注册完整后端")
	check(not registry.register_backend("first", second), "拒绝重复 id")
	check(registry.register_backend("second", second), "可并存第二个后端")
	check(registry.get_menu_actions().size() == 2, "多拓展菜单入口")
	check(registry.get_menu_pages().size() == 1, "页面接口可选，旧按钮提供者仍兼容")
	var page: Control = registry.get_menu_pages()[0].create_page.call()
	check(page.get_parent() == null, "页面工厂返回未挂载控件")
	page.free()
	check(registry.start_backend("first", {}, true), "受理异步准备")
	check(not registry.start_backend("second", {}, true), "准备期间拒绝重复启动")
	first.prepared.emit({"port": 24591, "host": true, "share_text": "10.0.0.1:24591"})
	check(session.installed_port == 24591 and registry.is_active(), "接入官方 ENet")
	check(first.stops == 0, "安装 ENet 不停止刚准备好的组网")
	check(registry.get_share_text() == "10.0.0.1:24591", "公开分享地址")
	registry.close(true)
	check(first.stops == 0 and registry.is_active(), "传输重连保留组网")
	registry.cancel("first")
	check(first.stops == 1 and not registry.is_active(), "显式取消释放后端")
	first.prepared.emit({"port": 24592, "host": true})
	check(session.installed_port == 24591, "取消后旧就绪通知无效")
	registry.start_backend("first", {}, true)
	first.failed.emit("old failure")
	registry.cancel("first")
	registry.start_backend("second", {}, false)
	second.prepared.emit({"port": 24593, "host": false})
	await process_frame
	check(session.installed_port == 24593 and registry.is_active(), "旧延迟故障不关闭新后端")
	second.failed.emit("current failure")
	await process_frame
	check(session.menu_returns == 1 and not registry.is_active(), "在线后端故障走官方回菜单")
	registry.start_backend("first", {}, true)
	first.prepared.emit({"port": 0, "host": true})
	await process_frame
	check(not registry.is_active(), "非法端点必须清理")
	first.accepted = false
	check(not registry.start_backend("first", {}, true), "同步拒绝返回 false")
	await process_frame
	check(not registry.is_active() and not registry.is_preparing(), "同步拒绝即使不发信号也会清理")
	registry.unregister_backend("second")
	check(registry.get_menu_actions().size() == 1, "移除拓展撤销入口")
	check(registry.get_menu_pages().is_empty(), "移除拓展撤销页面描述")
	first.queue_free()
	second.queue_free()
	session.queue_free()
	await process_frame
	print("EXTENSION_CONTRACT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

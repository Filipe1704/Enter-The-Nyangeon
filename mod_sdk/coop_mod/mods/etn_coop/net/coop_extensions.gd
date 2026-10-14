extends Node

## 官方联机拓展接口 v1。拓展只准备 ENet 端点；握手、重连与玩法仍由 CoopNet 管理。
## provider 必须有 prepared(endpoint)、failed(message) 信号及 start(plan, hosting)、stop()、diagnostics()。
## endpoint = {port, host, share_text?}；客机端点固定为回环，不接受拓展注入 RPC/玩法实现。
const API_VERSION := 1
signal state_changed(id: String, state: String, message: String)

var _session: Node
var _providers: Dictionary = {}
var _active := ""
var _preparing := false
var _installing := false
var _generation := 0
var _share_text := ""

func setup(session: Node) -> void:
	_session = session
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("CoopExtensionHost")

func get_api_version() -> int:
	return API_VERSION

func register_backend(id: String, provider: Node) -> bool:
	if id.is_empty() or _providers.has(id) or not is_instance_valid(provider):
		return false
	for method in ["start", "stop", "diagnostics"]:
		if not provider.has_method(method):
			return false
	if not provider.has_signal("prepared") or not provider.has_signal("failed"):
		return false
	_providers[id] = provider
	provider.connect("prepared", _on_prepared.bind(id))
	provider.connect("failed", _on_failed.bind(id))
	provider.tree_exiting.connect(unregister_backend.bind(id), CONNECT_ONE_SHOT)
	return true

func unregister_backend(id: String) -> void:
	if _active == id:
		cancel(id)
	var provider = _providers.get(id)
	if is_instance_valid(provider):
		if provider.is_connected("prepared", _on_prepared.bind(id)):
			provider.disconnect("prepared", _on_prepared.bind(id))
		if provider.is_connected("failed", _on_failed.bind(id)):
			provider.disconnect("failed", _on_failed.bind(id))
	_providers.erase(id)

func get_menu_actions() -> Array:
	var actions: Array = []
	for id in _providers:
		var provider = _providers[id]
		if is_instance_valid(provider) and provider.has_method("open_menu"):
			actions.append({"id": id, "title": str(provider.get("menu_title")), "activate": Callable(provider, "open_menu"),
				"create_button": Callable(provider, "create_menu_button") if provider.has_method("create_menu_button") else Callable()})
	return actions

func get_menu_pages() -> Array:
	var pages: Array = []
	for id in _providers:
		var provider = _providers[id]
		if is_instance_valid(provider) and provider.has_method("create_menu_page"):
			pages.append({"id": id, "title": str(provider.get("menu_title")),
				"create_page": Callable(provider, "create_menu_page")})
	return pages

func start_backend(id: String, plan: Dictionary, hosting: bool) -> bool:
	var provider = _providers.get(id)
	if not is_instance_valid(provider) or _preparing or _session.is_connect_in_flight():
		return false
	# 显式开始新会话，不能让旧重连标志阻止清理。
	_session.close_session()
	_active = id
	_preparing = true
	_generation += 1
	state_changed.emit(id, "preparing", "")
	var accepted := bool(provider.start(plan, hosting))
	if not accepted and _active == id and _preparing:
		_on_failed("Extension preparation failed", id)
	return accepted

func cancel(id: String) -> void:
	if _active == id:
		_session.close_session()

func close(keep_session: bool = false) -> void:
	if keep_session or _installing:
		return
	var id := _active
	var provider = _providers.get(id)
	_active = ""
	_preparing = false
	_share_text = ""
	_generation += 1
	if is_instance_valid(provider):
		provider.stop()
	if not id.is_empty():
		state_changed.emit(id, "idle", "")

func is_preparing() -> bool:
	return _preparing

func is_active() -> bool:
	return not _active.is_empty()

func get_share_text() -> String:
	return _share_text

func _on_prepared(endpoint: Dictionary, id: String) -> void:
	if id != _active or not _preparing:
		return
	var port := int(endpoint.get("port", 0))
	if port < 1 or port > 65535 or not endpoint.get("host") is bool:
		_on_failed("Invalid extension endpoint", id)
		return
	_installing = true
	var ok: bool = _session.host_game(port) if endpoint.host else _session.join_game("127.0.0.1", port)
	_installing = false
	_preparing = false
	if not ok:
		_on_failed("Extension transport failed", id)
		return
	_share_text = str(endpoint.get("share_text", ""))
	state_changed.emit(id, "ready", "")

func _on_failed(message: String, id: String) -> void:
	if id != _active:
		return
	_preparing = false
	# 后端可在信号栈报告故障，延迟关闭并校验代次，不能误关后来建立的会话。
	_fail_later.call_deferred(id, _generation, message)

func _fail_later(id: String, generation: int, message: String) -> void:
	if id != _active or generation != _generation:
		return
	var in_session: bool = bool(_session.is_lan_game)
	if in_session:
		_session.return_to_menu_after_disconnect()
	else:
		_session.close_session()
	state_changed.emit(id, "failed", message)

func _exit_tree() -> void:
	close()

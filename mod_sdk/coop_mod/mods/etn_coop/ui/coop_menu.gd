extends Control

## 联机菜单覆盖层（option 菜单式布局：左侧 option_button 页签 + 右侧内容面板）。
## 页签复用 `res://ui/option_button.tscn`；颜色统一为绿色。通过 CoopNet.instance 管理连接。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const MobileNoticeScene := preload("res://ui/mobile_notice.tscn")
const ROW_FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")

enum CoopPanelMode { LAN, RELAY, DEDICATED, OPTION, EXTENSION }

const TAB_GREEN := Color(0.0, 0.837, 0.295)
const TEXT_MUTED := Color(0.74902, 0.780392, 0.764706)
const INFO_COLOR := Color(0.498039, 0.847059, 1.0)
const WARN_COLOR := Color(1.0, 0.78, 0.12)
const DANGER_COLOR := Color(0.95, 0.18, 0.12)
const OK_COLOR := Color(0.2, 0.9, 0.35)
const OFFLINE_COLOR := Color(0.45, 0.45, 0.45)
const SCAN_DOT_INTERVAL := 0.38

var on_coop: bool = false
var _selected_mode: int = CoopPanelMode.LAN
var _lan_status_message: String = "offline"
var on_lan: bool = false
var on_relay: bool = false
var nav_index: int = 0
var _player_id_notice: Node = null
var _active_tab: Node = null
var _room_list: VBoxContainer = null
var _room_status_label: Label = null
var _room_count_label: Label = null
var _room_keys: Array = []
var _browsing: bool = false
var _scanning_active: bool = false
var _scan_elapsed: float = 0.0
var _scan_phase: int = 1
# 覆盖层内所有可交互控件；新增按钮/输入/开关必须登记此处（_set_buttons_enabled 只恢复名单内的 mouse_filter）。
var _interactive_controls: Array[Control] = []
# 中继服务器列表：主面板按钮 + 子菜单（触摸可拖拽滚动）+ 二次确认
var _server_list_button: Button = null
var _server_submenu: Control = null
var _server_submenu_scroll: ScrollContainer = null
var _relay_saved_list: VBoxContainer = null
var _submenu_name_input: LineEdit = null
var _submenu_addr_input: LineEdit = null
var _submenu_save_button: Button = null
var _submenu_close_button: Button = null
var _saved_confirm: ConfirmationDialog = null
var _pending_delete_addr: String = ""
var _extension_buttons: Array[Control] = []
var _extension_pages: Dictionary = {}
var _selected_extension: String = ""
var _extension_mouse_filters: Dictionary = {}
var _extension_focus_modes: Dictionary = {}
var _extension_statuses: Dictionary = {}
var _active_extension_status: String = ""

@onready var _panel: PanelContainer = $Panel
var _page_scroll: ScrollContainer = null
@onready var _ip_input: LineEdit = %IpInput
@onready var _port_input: LineEdit = %PortInput
@onready var _public_ip_input: LineEdit = %PublicIpInput
@onready var _public_ip_clear: Button = %PublicIpClear
@onready var _manual_ip_hint: Label = %ManualIpHint
@onready var _coop_option: Node = %CoopOption
@onready var _join_button: Button = %JoinButton
@onready var _host_button: Button = %HostButton
@onready var _mode_subtitle_label: Label = %ModeSubtitleLabel
@onready var _dedicated_panel: VBoxContainer = %DedicatedPanel
@onready var _relay_server_input: LineEdit = %RelayServerInput
@onready var _relay_room_input: LineEdit = %RelayRoomInput
@onready var _relay_create_button: Button = %RelayCreateButton
@onready var _relay_join_button: Button = %RelayJoinButton
@onready var _relay_room_code_label: Label = %RelayRoomCodeLabel
@onready var _status_label: Label = %StatusLabel
@onready var _local_ip_label: Label = %LocalIpLabel
@onready var _status_dot: ColorRect = %StatusDot

@onready var _lan_panel: VBoxContainer = %LanPanel
@onready var _relay_panel: VBoxContainer = %RelayPanel
@onready var _option_panel: VBoxContainer = %OptionPanel
@onready var _player_id_input: LineEdit = %PlayerIdInput
@onready var _player_id_confirm: Button = %PlayerIdConfirm
@onready var _addr_lan_toggle = %LanAddrToggle
@onready var _addr_public_toggle = %PublicAddrToggle
@onready var lan: PanelContainer = %LAN
@onready var relay: PanelContainer = %Relay
@onready var option: PanelContainer = %Option
@onready var lan_option_player: AnimationPlayer = lan.get_node("AnimationPlayer")
@onready var relay_option_player: AnimationPlayer = relay.get_node("AnimationPlayer")
@onready var option_option_player: AnimationPlayer = option.get_node("AnimationPlayer")
@onready var panel_animator: AnimationPlayer = %PanelAnimator
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var _banner: TextureRect = %Banner


func _resolve_page_scroll() -> ScrollContainer:
	if _page_scroll != null and is_instance_valid(_page_scroll):
		return _page_scroll
	_page_scroll = get_node_or_null("%PageScroll") as ScrollContainer
	if _page_scroll == null:
		_page_scroll = get_node_or_null("Panel/RootHBox/ContentRoot/PageScroll") as ScrollContainer
	return _page_scroll


func _ready() -> void:
	_resolve_page_scroll()
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_relay_create_button.pressed.connect(_on_relay_create_pressed)
	_relay_join_button.pressed.connect(_on_relay_join_pressed)
	_host_button.gui_input.connect(_on_host_gui_input)
	_join_button.gui_input.connect(_on_join_gui_input)
	_ip_input.gui_input.connect(_on_ip_input_gui_input)
	_port_input.gui_input.connect(_on_port_input_gui_input)
	_public_ip_input.gui_input.connect(_on_public_ip_input_gui_input)
	_public_ip_input.text_submitted.connect(_on_public_ip_submitted)
	_public_ip_input.focus_exited.connect(_on_public_ip_focus_exited)
	_public_ip_clear.pressed.connect(_on_public_ip_clear_pressed)
	_relay_server_input.gui_input.connect(_on_relay_server_input_gui_input)
	_relay_room_input.gui_input.connect(_on_relay_room_input_gui_input)
	_relay_create_button.gui_input.connect(_on_relay_create_gui_input)
	_relay_join_button.gui_input.connect(_on_relay_join_gui_input)

	# option_button 自身会 play("selected") 并 emit GameEvents.menu_button(button_id)
	GameEvents.menu_button.connect(_on_menu_button)

	var coop = CoopNetScript.instance
	if coop != null:
		coop.connection_status_changed.connect(_on_connection_status_changed)
		coop.character_select_requested.connect(out_coop_selected)
		coop.relay_room_created.connect(_on_relay_room_created)
		coop.extensions.state_changed.connect(_on_extension_state_changed)

	_apply_tab_color(lan)
	_apply_tab_color(relay)
	_apply_tab_color(option)
	_setup_tab_input(lan)
	_setup_tab_input(relay)
	_setup_tab_input(option)
	_setup_tabs_container()
	_load_banner_texture()
	_setup_return_button()
	animation_player.animation_finished.connect(_on_page_anim_finished)
	_addr_lan_toggle.toggled.connect(_on_lan_addr_toggled)
	_addr_public_toggle.toggled.connect(_on_public_addr_toggled)
	_player_id_confirm.pressed.connect(_on_player_id_confirm_pressed)
	_player_id_input.text_submitted.connect(_on_player_id_text_submitted)
	_player_id_input.gui_input.connect(_on_player_id_input_gui_input)
	_player_id_confirm.gui_input.connect(_on_player_id_confirm_gui_input)
	_player_id_notice = MobileNoticeScene.instantiate()
	add_child(_player_id_notice)
	_refresh_player_id_input()
	_refresh_lan_port_input()
	_refresh_addr_mode()
	_refresh_manual_ip()
	_build_room_list()
	_setup_saved_confirm()
	_build_server_list_button()
	_build_server_submenu()
	_build_extension_actions()
	_build_extension_pages()
	_build_interactive_controls()

	visible = false
	panel_animator.play("panel_option_out")
	_update_local_ip_label()
	_select_mode(CoopPanelMode.LAN, false)
	_set_status("offline", "LAN")
	_set_buttons_enabled(false)


# ---------------- LAN 房间列表（UDP 发现） ----------------

func _build_room_list() -> void:
	_room_list = get_node_or_null("%RoomList") as VBoxContainer
	_room_status_label = get_node_or_null("%RoomStatus") as Label
	_room_count_label = get_node_or_null("%RoomCount") as Label
	if _room_list == null:
		return
	_room_list.add_theme_constant_override("separation", 4)
	_refresh_room_status(0, false)


func _process(_delta: float) -> void:
	var coop = CoopNetScript.instance
	# 隐藏时只补一次「停广播 + 清房间列表」，其余每帧刷新（房间列表/UPnP 提示）无意义。
	if not visible:
		if _browsing:
			_browsing = false
			if coop != null and is_instance_valid(coop):
				coop.call("browse_lan_stop")
			_clear_room_list()
			_refresh_room_status(0, false)
		return
	var browsing: bool = _selected_mode == CoopPanelMode.LAN \
			and (coop == null or not bool(coop.is_lan_game))
	if browsing != _browsing:
		_browsing = browsing
		if coop != null and is_instance_valid(coop):
			coop.call("browse_lan_start" if browsing else "browse_lan_stop")
		if not browsing:
			_clear_room_list()
			_refresh_room_status(0, false)
	if _browsing and coop != null and is_instance_valid(coop):
		_refresh_room_list(coop)
	_tick_scan_dots(_delta)
	_refresh_manual_ip_hint(coop)


func _clear_room_list() -> void:
	if _room_list == null:
		return
	for c in _room_list.get_children():
		for child in c.get_children():
			_interactive_controls.erase(child)
		_room_list.remove_child(c)
		_interactive_controls.erase(c)
		c.queue_free()
	_room_keys = []


func _refresh_room_list(coop: Node) -> void:
	if _room_list == null:
		return
	var rooms: Array = coop.call("get_lan_rooms")
	var keys: Array = []
	for r in rooms:
		keys.append("%s:%d:%d" % [str(r.get("ip", "")), int(r.get("port", 0)), int(r.get("players", 0))])
	if keys == _room_keys:
		_refresh_room_status(rooms.size(), _browsing)
		return
	_clear_room_list()
	_room_keys = keys
	for r in rooms:
		var name := str(r.get("name", ""))
		var players := int(r.get("players", 0))
		var max_players := int(r.get("max", 0))
		var ip := str(r.get("ip", ""))
		var port := int(r.get("port", 0))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_room_list.add_child(row)
		var b := Button.new()
		b.text = "%s  %d/%d" % [name, players, max_players]
		b.tooltip_text = "%s:%d" % [ip, port]
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(0, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on_coop else Control.MOUSE_FILTER_IGNORE
		b.pressed.connect(_on_room_pressed.bind(ip, port))
		row.add_child(b)
		_interactive_controls.append(b)
		var addr := Label.new()
		addr.text = "%s:%d" % [ip, port]
		addr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		addr.add_theme_font_override("font", ROW_FONT)
		addr.add_theme_font_size_override("font_size", 9)
		addr.add_theme_color_override("font_color", INFO_COLOR)
		addr.clip_text = true
		row.add_child(addr)
	_refresh_room_status(rooms.size(), _browsing)


func _refresh_room_status(room_count: int, browsing: bool) -> void:
	if _room_count_label != null:
		_room_count_label.text = "(%d)" % room_count if room_count > 0 else ""
	if _room_status_label == null:
		return
	if room_count > 0:
		_scanning_active = false
		_room_status_label.text = ""
		_room_status_label.visible = false
		return
	var was_scanning := _scanning_active
	_scanning_active = false
	if browsing:
		if not was_scanning:
			_scan_elapsed = 0.0
			_scan_phase = 1
		_scanning_active = true
		_room_status_label.add_theme_color_override("font_color", WARN_COLOR)
		_room_status_label.text = _scanning_text()
		_room_status_label.visible = true
	else:
		_room_status_label.add_theme_color_override("font_color", TEXT_MUTED)
		_room_status_label.text = tr("coop_lan_no_rooms")
		_room_status_label.visible = true


func _scanning_text() -> String:
	return tr("coop_lan_scanning_base") + ".".repeat(_scan_phase)


func _tick_scan_dots(delta: float) -> void:
	if not _scanning_active or _room_status_label == null:
		return
	_scan_elapsed += delta
	if _scan_elapsed < SCAN_DOT_INTERVAL:
		return
	_scan_elapsed = fmod(_scan_elapsed, SCAN_DOT_INTERVAL)
	_scan_phase = _scan_phase % 3 + 1
	_room_status_label.text = _scanning_text()


func _on_room_pressed(ip: String, port: int) -> void:
	_ip_input.text = ip
	if _port_input != null and port > 0 and port <= 65535:
		_port_input.text = str(port)
	_on_join_pressed()


func _apply_tab_color(tab: Node) -> void:
	var bar := tab.get_node_or_null("Node2D/ColorRect")
	if bar != null:
		bar.color = TAB_GREEN


# option_button 根为 MOUSE_FILTER_IGNORE，且未选中时内部高亮 ColorRect 宽度为 0，
# 因此未选中页签没有有效命中区。把整块页签根设为唯一命中目标（子节点全部 IGNORE），
# 从而恢复悬停（根自带 mouse_entered/exited）与点击（根 gui_input + shoot）。
func _setup_tab_input(tab: Node) -> void:
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	tab.focus_mode = Control.FOCUS_ALL
	for child in tab.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := tab.get_node_or_null("Node2D")
	if inner != null:
		for child in inner.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _tabs_vbox() -> Control:
	var box := get_node_or_null("Node2D/option_button_box/VBoxContainer")
	if box == null:
		box = get_node_or_null("Node2D/VBoxContainer")
	return box


func _setup_tabs_container() -> void:
	var box := _tabs_vbox()
	if box is Control:
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _load_banner_texture() -> void:
	if _banner == null:
		return
	var bytes := FileAccess.get_file_as_bytes("res://mods/etn_coop/ui/coop_icon.png")
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	_banner.texture = ImageTexture.create_from_image(img)


func _setup_return_button() -> void:
	var ret := get_node_or_null("Node2D/return")
	if ret == null:
		return
	# 覆盖本体 return.gd 的 pause_press 行为：仅关闭本覆盖层
	var cb := Callable(ret, "_on_gui_input")
	if ret.gui_input.is_connected(cb):
		ret.gui_input.disconnect(cb)
	if not ret.pressed.is_connected(out_coop_selected):
		ret.pressed.connect(out_coop_selected)


func _on_page_anim_finished(anim_name: StringName) -> void:
	if anim_name == "coop_out" and not on_coop:
		visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not on_coop:
		return
	if not _is_gamepad_event(event):
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_move_nav(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_move_nav(-1)
		get_viewport().set_input_as_handled()
	elif _is_ui_accept(event):
		_activate_nav()
		get_viewport().set_input_as_handled()


func _handle_cancel_input(event: InputEvent) -> bool:
	if not on_coop:
		return false
	if _saved_confirm != null and _saved_confirm.visible:
		return false
	if not _is_ui_cancel(event):
		return false
	if _server_submenu != null and _server_submenu.visible:
		_close_server_submenu()
	else:
		out_coop_selected()
	get_viewport().set_input_as_handled()
	return true


# 滚轮兜底：覆盖整个页面矩形，即使指针停在按钮/输入框/滑条上也让页面滚动。
func _input(event: InputEvent) -> void:
	if not on_coop:
		return
	if _handle_cancel_input(event):
		return
	if _server_submenu != null and _server_submenu.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if _page_scroll == null or not is_instance_valid(_page_scroll):
		_resolve_page_scroll()
	if _page_scroll == null or not is_instance_valid(_page_scroll):
		return
	if not _page_scroll.get_global_rect().has_point(mb.position):
		return
	var step := int(48.0 * maxf(1.0, mb.factor))
	var delta := -step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else step
	_page_scroll.scroll_vertical += delta
	get_viewport().set_input_as_handled()


func _is_ui_accept(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot")


func _is_ui_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")


func _is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _get_nav_items() -> Array[Control]:
	var items: Array[Control] = [lan, relay]
	for entry in _extension_pages.values():
		items.append(entry.tab)
	items.append(option)
	items.append_array(_extension_buttons)
	# 玩家 ID 行常驻顶部（所有页签通用）
	items.append(_player_id_input)
	items.append(_player_id_confirm)
	if _selected_mode == CoopPanelMode.LAN:
		items.append(_host_button)
		items.append(_ip_input)
		items.append(_join_button)
	elif _selected_mode == CoopPanelMode.RELAY:
		items.append(_relay_server_input)
		items.append(_relay_create_button)
		if _server_list_button != null:
			items.append(_server_list_button)
		items.append(_relay_room_input)
		items.append(_relay_join_button)
	elif _selected_mode == CoopPanelMode.OPTION:
		if _coop_option != null and is_instance_valid(_coop_option) and _coop_option.has_method("get_interactive_controls"):
			for c in _coop_option.call("get_interactive_controls"):
				if c is Control:
					items.append(c)
	elif _selected_mode == CoopPanelMode.EXTENSION:
		var page: Control = _extension_pages[_selected_extension].page
		for control in page.get_interactive_controls():
			if control is Control and control.focus_mode != Control.FOCUS_NONE:
				items.append(control)
	var visible_items: Array[Control] = []
	for item in items:
		if item.is_visible_in_tree() and not (item is BaseButton and item.disabled):
			visible_items.append(item)
	return visible_items


func _move_nav(step: int) -> void:
	var items: Array[Control] = _get_nav_items()
	if items.is_empty():
		return
	# 页签切换后条目数可能变少，先夹取索引，避免 items[nav_index] 越界
	nav_index = clampi(nav_index, 0, items.size() - 1)
	_unfocus_nav(items[nav_index])
	nav_index = posmod(nav_index + step, items.size())
	_focus_nav(items[nav_index])


func _focus_nav(item: Control) -> void:
	if item == lan:
		mouse_on_lan()
	elif item == relay:
		mouse_on_relay()
	elif item == option:
		mouse_on_option()
	elif _extension_id_for_tab(item) != "":
		item.call("mouse_entered_anim")
	else:
		item.grab_focus()
		SoundManager.play_sfx("ButtonSounds2")


func _unfocus_nav(item: Control) -> void:
	if item == lan:
		mouse_out_lan()
	elif item == relay:
		mouse_out_relay()
	elif item == option:
		mouse_out_option()
	elif _extension_id_for_tab(item) != "":
		item.call("mouse_exitedd_anim")


func _activate_nav() -> void:
	var items: Array[Control] = _get_nav_items()
	if items.is_empty():
		return
	nav_index = clamp(nav_index, 0, items.size() - 1)
	var item: Control = items[nav_index]
	if item == lan:
		_set_selected_mode(CoopPanelMode.LAN)
		nav_index = 0
	elif item == relay:
		_set_selected_mode(CoopPanelMode.RELAY)
		nav_index = 1
	elif item == option:
		_set_selected_mode(CoopPanelMode.OPTION)
	elif _extension_id_for_tab(item) != "":
		_select_extension(_extension_id_for_tab(item))
	elif item is LineEdit:
		item.grab_focus()
		DisplayServer.virtual_keyboard_show(item.text)
	elif item is Button:
		item.emit_signal("pressed")


func on_coop_selected() -> void:
	_resolve_page_scroll()
	on_coop = true
	visible = true
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	_set_buttons_enabled(true)
	if _coop_option != null and is_instance_valid(_coop_option) and _coop_option.has_method("refresh"):
		_coop_option.call("refresh")
	_play_in()
	nav_index = 0
	if _page_scroll != null:
		_page_scroll.scroll_vertical = 0
	if Game.control_mode == 2 and not _get_nav_items().is_empty():
		_focus_nav(_get_nav_items()[nav_index])


func out_coop_selected() -> void:
	SoundManager.play_sfx("UISounds2")
	_close_server_submenu()
	on_coop = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		get_viewport().gui_release_focus()
	_set_buttons_enabled(false)
	_play_out()


# 集中登记覆盖层内所有可交互控件（新增按钮/输入/开关必须加到这里，否则会被下面
# 的「后代统一 IGNORE」流程留在不可点击状态——UPnP 开关/端口框曾因此点不动）。
func _build_interactive_controls() -> void:
	_resolve_page_scroll()
	_interactive_controls = [
		_host_button, _join_button, _ip_input, _port_input,
		_public_ip_input, _public_ip_clear,
		_relay_server_input, _relay_room_input, _relay_create_button, _relay_join_button, _server_list_button,
		option, _player_id_input, _player_id_confirm,
		_addr_lan_toggle, _addr_public_toggle, _page_scroll,
	]
	if _page_scroll != null:
		var vbar := _page_scroll.get_v_scroll_bar()
		if vbar != null:
			_interactive_controls.append(vbar)
	_interactive_controls.append_array(_extension_buttons)
	for entry in _extension_pages.values():
		var controls: Array = [entry.tab]
		controls.append_array(entry.page.get_interactive_controls())
		for control in controls:
			_interactive_controls.append(control)
			_extension_mouse_filters[control] = control.mouse_filter
			_extension_focus_modes[control] = control.focus_mode
	# 可复用 coop 选项内容（滑条/开关/自检按钮）也登记进白名单
	if _coop_option != null and is_instance_valid(_coop_option) and _coop_option.has_method("get_interactive_controls"):
		for c in _coop_option.call("get_interactive_controls"):
			if c != null and is_instance_valid(c):
				_interactive_controls.append(c)


func _build_extension_actions() -> void:
	var coop = CoopNetScript.instance
	if coop == null:
		return
	var actions: Array = coop.extensions.get_menu_actions()
	if actions.is_empty():
		return
	var row := HBoxContainer.new()
	row.name = "ExtensionActions"
	var content := _panel.get_node("RootHBox/ContentRoot")
	content.add_child(row)
	content.move_child(row, content.get_node("StatusBox").get_index())
	for action in actions:
		var button: Button = action.create_button.call() if action.create_button.is_valid() else Button.new()
		button.name = str(action.id)
		button.text = str(action.title)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(action.activate)
		row.add_child(button)
		_extension_buttons.append(button)


func _build_extension_pages() -> void:
	var coop = CoopNetScript.instance
	if coop == null:
		return
	var content := _panel.get_node("RootHBox/ContentRoot/PageScroll/PageContent")
	var tabs := _tabs_vbox()
	if tabs == null:
		push_warning("[etn_coop] 找不到页签容器 Node2D/option_button_box/VBoxContainer")
		return
	for descriptor in coop.extensions.get_menu_pages():
		var page = descriptor.create_page.call()
		if not page is Control or page.get_parent() != null or not page.has_method("get_interactive_controls"):
			push_warning("[etn_coop] 拓展页须返回未挂载且提供交互名单的 Control：%s" % descriptor.id)
			if page is Node and page.get_parent() == null:
				page.queue_free()
			continue
		page.visible = false
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(page)
		var tab := ModAPI.create_option_tab("coop_extension_" + str(descriptor.id), str(descriptor.title))
		tab.get_node("Label").add_theme_font_size_override("font_size", 14)
		tabs.add_child(tab)
		tabs.move_child(tab, option.get_index())
		tab.focus_mode = Control.FOCUS_ALL
		_apply_tab_color(tab)
		_setup_tab_input(tab)
		_extension_pages[str(descriptor.id)] = {"tab": tab, "page": page, "title": str(descriptor.title)}
		var provider: Object = descriptor.create_page.get_object()
		var details: Dictionary = provider.diagnostics()
		_on_extension_state_changed(str(descriptor.id), str(details.get("state", "idle")), "")


func _extension_id_for_tab(tab: Control) -> String:
	for id in _extension_pages:
		if _extension_pages[id].tab == tab:
			return id
	return ""


func _select_extension(id: String) -> void:
	if not _extension_pages.has(id):
		return
	_selected_extension = id
	_set_selected_mode(CoopPanelMode.EXTENSION, false)


func _set_buttons_enabled(enabled: bool) -> void:
	_resolve_page_scroll()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in _panel.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in _interactive_controls:
		if c != null and is_instance_valid(c):
			c.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
			c.mouse_force_pass_scroll_events = true
	# 拓展滚动页保留 PASS 冒泡；关闭菜单时同时撤销其键盘焦点。
	for control in _extension_mouse_filters:
		control.mouse_filter = _extension_mouse_filters[control] if enabled else Control.MOUSE_FILTER_IGNORE
		control.focus_mode = _extension_focus_modes[control] if enabled else Control.FOCUS_NONE
	# 滚条可能晚于 _build_interactive_controls() 才创建，启用时再动态恢复一次。
	if _page_scroll != null and is_instance_valid(_page_scroll):
		_page_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		_page_scroll.mouse_force_pass_scroll_events = true
		var vbar := _page_scroll.get_v_scroll_bar()
		if vbar != null:
			vbar.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _play_in() -> void:
	animation_player.play("coop_in")


func _play_out() -> void:
	animation_player.play("coop_out")


func _on_host_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_update_local_ip_label()
	var coop = CoopNetScript.instance
	# 开房成功后 CoopNet 自动进入准备房（测试房）
	if coop != null:
		var port: int = _parse_port()
		coop.call("host_game", port)


func _on_join_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop == null:
		return
	# 支持直接粘贴 "主机:端口"（内网穿透地址常带端口）：拆出端口回填并覆盖 PortInput
	var raw: String = _ip_input.text.strip_edges()
	var parsed: Dictionary = coop.call("parse_host_port", raw)
	var host: String = str(parsed.get("host", raw))
	var p: int = int(parsed.get("port", -1))
	if p > 0 and p <= 65535 and _port_input != null:
		_port_input.text = str(p)
	coop.call("join_game", host, _parse_port())


# 端口解析：1–65535；空/非法回退默认；持久化最近一次可用值。
func _parse_port() -> int:
	var fallback: int = int(CoopNetScript.DEFAULT_PORT)
	var text: String = _port_input.text.strip_edges() if _port_input != null else ""
	var port: int = fallback
	if text.is_valid_int():
		port = int(text)
	if port < 1 or port > 65535:
		port = fallback
	var coop = CoopNetScript.instance
	if coop != null:
		var s = coop.get("settings")
		if s != null and int(s.get("lan_port")) != port:
			s.call("apply_lan_port", port)
	return port


func _refresh_lan_port_input() -> void:
	var coop = CoopNetScript.instance
	var port: int = int(CoopNetScript.DEFAULT_PORT)
	if coop != null:
		var s = coop.get("settings")
		if s != null:
			port = int(s.get("lan_port"))
	_port_input.text = str(port)


func _select_mode(mode: int, play_sound: bool = true) -> void:
	_set_selected_mode(mode, play_sound)


func _set_selected_mode(mode: int, play_sound: bool = true) -> void:
	if play_sound:
		SoundManager.play_sfx("ButtonSounds")
	_selected_mode = mode
	on_lan = mode == CoopPanelMode.LAN
	on_relay = mode == CoopPanelMode.RELAY
	_lan_panel.visible = on_lan
	_relay_panel.visible = on_relay
	_dedicated_panel.visible = mode == CoopPanelMode.DEDICATED
	_option_panel.visible = mode == CoopPanelMode.OPTION
	for id in _extension_pages:
		_extension_pages[id].page.visible = mode == CoopPanelMode.EXTENSION and id == _selected_extension
	match mode:
		CoopPanelMode.LAN:
			_mode_subtitle_label.text = "coop_mode_subtitle_lan"
			_set_status(_lan_status_message, "LAN")
		CoopPanelMode.RELAY:
			_mode_subtitle_label.text = "coop_mode_subtitle_relay"
			_set_status(_lan_status_message, "RELAY")
		CoopPanelMode.DEDICATED:
			_mode_subtitle_label.text = "coop_mode_subtitle_dedicated"
			_set_status("coop_status_dedicated_unavailable", "DEDICATED")
		CoopPanelMode.OPTION:
			_mode_subtitle_label.text = "coop_mode_subtitle_option"
			_set_status(_lan_status_message, "OPTION")
			if _coop_option != null and is_instance_valid(_coop_option) and _coop_option.has_method("refresh"):
				_coop_option.call("refresh")
		CoopPanelMode.EXTENSION:
			_mode_subtitle_label.text = _extension_pages[_selected_extension].title
			_refresh_extension_status()
	_update_mode_visuals(mode)
	_resolve_page_scroll()
	if _page_scroll != null:
		_page_scroll.scroll_vertical = 0


func _update_mode_visuals(mode: int) -> void:
	panel_animator.play("panel_option_out")
	var new_tab: Node = _tab_for_mode(mode)
	# 只收回「上一个选中」的页签；未被选中的页签不动（否则每次点击三个页签都会播收回）。
	if _active_tab != null and _active_tab != new_tab:
		_deselect_tab(_active_tab)
	_active_tab = new_tab
	if new_tab != null:
		new_tab.set("on_show", true)
		var tab_anim: AnimationPlayer = new_tab.get_node("AnimationPlayer")
		if tab_anim.current_animation != "selected":
			tab_anim.play("selected")
	panel_animator.play("panel_option_in")


func _tab_for_mode(mode: int) -> Node:
	match mode:
		CoopPanelMode.LAN:
			return lan
		CoopPanelMode.RELAY:
			return relay
		CoopPanelMode.OPTION:
			return option
		CoopPanelMode.EXTENSION:
			return _extension_pages[_selected_extension].tab
	return null


func _deselect_tab(tab: Node) -> void:
	tab.set("on_show", false)
	tab.get_node("AnimationPlayer").play_backwards("on_select")


func _on_menu_button(button_id: String) -> void:
	if not on_coop:
		return
	for id in _extension_pages:
		if button_id == _extension_pages[id].tab.button_id:
			_select_extension(id)
			return
	if button_id == "coop_lan":
		if _selected_mode != CoopPanelMode.LAN:
			SoundManager.play_sfx("ButtonSounds")
			_set_selected_mode(CoopPanelMode.LAN, false)
	elif button_id == "coop_relay":
		if _selected_mode != CoopPanelMode.RELAY:
			SoundManager.play_sfx("ButtonSounds")
			_set_selected_mode(CoopPanelMode.RELAY, false)
	elif button_id == "coop_option":
		if _selected_mode != CoopPanelMode.OPTION:
			SoundManager.play_sfx("ButtonSounds")
			_set_selected_mode(CoopPanelMode.OPTION, false)


func _on_relay_create_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop == null:
		return
	# 进行中时忽略重复点击，避免创建多条连接/多个房间
	if coop.is_connect_in_flight():
		return
	var result: String = str(coop.create_relay_room(_relay_server_input.text))
	if result == "":
		_relay_room_code_label.text = "coop_room_code_empty"
		return
	# 建房成功后 CoopNet 自动进入准备房（测试房）
	_relay_room_code_label.text = "coop_room_code_creating"
	_set_relay_busy(true)


func _on_relay_room_created(room_code: String) -> void:
	_relay_room_code_label.text = tr("coop_room_code_value") % room_code
	_set_relay_busy(false)


func _on_relay_join_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop == null:
		return
	# 进行中时忽略重复点击：否则每次点击都会新建连接，被中继当作新成员反复排序
	if coop.is_connect_in_flight():
		return
	if coop.join_relay_room(_relay_server_input.text, _relay_room_input.text):
		_set_relay_busy(true)


# 中继连接进行中：禁用建房/加入按钮与输入，避免重复触发
func _set_relay_busy(busy: bool) -> void:
	if _relay_join_button != null:
		_relay_join_button.disabled = busy
	if _relay_create_button != null:
		_relay_create_button.disabled = busy
	if _relay_server_input != null:
		_relay_server_input.editable = not busy
	if _relay_room_input != null:
		_relay_room_input.editable = not busy


# ---------------- RELAY 页：已保存的服务器列表（名称+地址） ----------------

func _build_server_list_button() -> void:
	if _relay_panel == null:
		return
	_server_list_button = Button.new()
	_server_list_button.name = "ServerListButton"
	_server_list_button.custom_minimum_size = Vector2(150, 26)
	_server_list_button.text = "coop_server_list"
	_server_list_button.pressed.connect(_open_server_submenu)
	var saki_row := get_node_or_null("%SakiServerRow")
	if saki_row != null:
		saki_row.add_child(_server_list_button)
	else:
		_relay_panel.add_child(_server_list_button)


# 子菜单：挂在 CoopMenu 根下（不属于 _panel），故不受 _set_buttons_enabled 的后代 IGNORE 影响。
func _build_server_submenu() -> void:
	_server_submenu = Control.new()
	_server_submenu.name = "ServerSubmenu"
	_server_submenu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_server_submenu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_server_submenu.visible = false
	add_child(_server_submenu)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_submenu_backdrop_input)
	_server_submenu.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_server_submenu.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.101961, 0.101961, 0.101961, 1.0)
	sb.border_color = Color(0.223529, 0.223529, 0.223529, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_right = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "coop_saved_servers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", ROW_FONT)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.819608, 0.819608, 0.819608, 1))
	vbox.add_child(title)

	_server_submenu_scroll = ScrollContainer.new()
	_server_submenu_scroll.name = "ServerListScroll"
	_server_submenu_scroll.custom_minimum_size = Vector2(340, 230)
	_server_submenu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_server_submenu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_server_submenu_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	# 复用本体触摸/鼠标拖拽滚动脚本；必须在 add_child 前挂，否则 _ready 不跑、gui_input 不连。
	_server_submenu_scroll.set_script(load("res://script/ScrollBox.gd"))
	vbox.add_child(_server_submenu_scroll)

	_relay_saved_list = VBoxContainer.new()
	_relay_saved_list.name = "SavedServerList"
	_relay_saved_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relay_saved_list.add_theme_constant_override("separation", 4)
	_server_submenu_scroll.add_child(_relay_saved_list)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	vbox.add_child(add_row)
	_submenu_name_input = LineEdit.new()
	_submenu_name_input.custom_minimum_size = Vector2(110, 30)
	_submenu_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submenu_name_input.placeholder_text = "coop_server_name_placeholder"
	_submenu_name_input.gui_input.connect(_on_submenu_name_input_gui_input)
	add_row.add_child(_submenu_name_input)
	_submenu_addr_input = LineEdit.new()
	_submenu_addr_input.custom_minimum_size = Vector2(130, 30)
	_submenu_addr_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submenu_addr_input.placeholder_text = "coop_relay_server_placeholder"
	_submenu_addr_input.gui_input.connect(_on_submenu_addr_input_gui_input)
	add_row.add_child(_submenu_addr_input)
	_submenu_save_button = Button.new()
	_submenu_save_button.custom_minimum_size = Vector2(72, 30)
	_submenu_save_button.text = "coop_server_save"
	_submenu_save_button.pressed.connect(_on_saved_server_save_pressed)
	add_row.add_child(_submenu_save_button)

	_submenu_close_button = Button.new()
	_submenu_close_button.custom_minimum_size = Vector2(0, 30)
	_submenu_close_button.text = "coop_server_close"
	_submenu_close_button.pressed.connect(_close_server_submenu)
	vbox.add_child(_submenu_close_button)

	_rebuild_saved_servers()


func _open_server_submenu() -> void:
	SoundManager.play_sfx("ButtonSounds")
	if _server_submenu == null:
		return
	# 每次打开都清空输入框（干净起始态）
	if _submenu_name_input != null:
		_submenu_name_input.text = ""
	if _submenu_addr_input != null:
		_submenu_addr_input.text = ""
	_rebuild_saved_servers()
	_server_submenu.visible = true


func _close_server_submenu() -> void:
	if _server_submenu != null:
		_server_submenu.visible = false


func _setup_saved_confirm() -> void:
	_saved_confirm = ConfirmationDialog.new()
	_saved_confirm.ok_button_text = tr("coop_server_delete")
	_saved_confirm.cancel_button_text = tr("coop_cancel")
	_saved_confirm.confirmed.connect(_on_saved_delete_confirmed)
	add_child(_saved_confirm)


func _get_relay_servers() -> Array:
	var coop = CoopNetScript.instance
	if coop == null:
		return []
	var s = coop.get("settings")
	if s == null:
		return []
	var v = s.get("relay_servers")
	return v if v is Array else []


func _save_relay_servers(servers: Array) -> void:
	var coop = CoopNetScript.instance
	if coop == null:
		return
	var s = coop.get("settings")
	if s != null:
		s.call("apply_relay_servers", servers)


func _rebuild_saved_servers() -> void:
	if _relay_saved_list == null:
		return
	for c in _relay_saved_list.get_children():
		_relay_saved_list.remove_child(c)
		c.queue_free()
	var servers: Array = _get_relay_servers()
	if servers.is_empty():
		var lbl := Label.new()
		lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lbl.text = tr("coop_saved_empty")
		_relay_saved_list.add_child(lbl)
	else:
		for e in servers:
			if not (e is Dictionary):
				continue
			var addr: String = str(e.get("addr", ""))
			if addr == "":
				continue
			var nm: String = str(e.get("name", addr))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var pick := Button.new()
			pick.text = nm
			pick.tooltip_text = addr
			pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pick.pressed.connect(_on_saved_server_pressed.bind(addr))
			row.add_child(pick)
			var del := Button.new()
			del.text = "coop_server_delete"
			del.tooltip_text = "coop_server_delete"
			del.custom_minimum_size = Vector2(72, 0)
			del.pressed.connect(_on_saved_server_delete_pressed.bind(addr, nm))
			row.add_child(del)
			_relay_saved_list.add_child(row)


func _on_saved_server_pressed(addr: String) -> void:
	SoundManager.play_sfx("ButtonSounds")
	if _relay_server_input != null:
		_relay_server_input.text = addr
	_close_server_submenu()


func _on_saved_server_save_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var addr: String = _submenu_addr_input.text.strip_edges() if _submenu_addr_input != null else ""
	if addr == "":
		_notice("coop_server_invalid")
		return
	var nm: String = _submenu_name_input.text.strip_edges() if _submenu_name_input != null else ""
	if nm == "":
		nm = addr
	nm = nm.left(32)
	var servers: Array = _get_relay_servers()
	var updated := false
	for e in servers:
		if e is Dictionary and str(e.get("addr", "")) == addr:
			e["name"] = nm
			updated = true
			break
	if not updated:
		servers.append({"name": nm, "addr": addr})
	_save_relay_servers(servers)
	if _submenu_name_input != null:
		_submenu_name_input.text = ""
	if _submenu_addr_input != null:
		_submenu_addr_input.text = ""
	_rebuild_saved_servers()
	_notice("coop_server_saved")


func _on_saved_server_delete_pressed(addr: String, nm: String) -> void:
	SoundManager.play_sfx("ButtonSounds")
	_pending_delete_addr = addr
	if _saved_confirm != null:
		_saved_confirm.dialog_text = tr("coop_server_delete_confirm") % (nm if nm != "" else addr)
		_saved_confirm.popup_centered()


func _on_saved_delete_confirmed() -> void:
	var addr: String = _pending_delete_addr
	_pending_delete_addr = ""
	if addr == "":
		return
	var servers: Array = _get_relay_servers()
	var out: Array = []
	for e in servers:
		if e is Dictionary and str(e.get("addr", "")) == addr:
			continue
		out.append(e)
	_save_relay_servers(out)
	_rebuild_saved_servers()
	_notice("coop_server_removed")


func _notice(key: String) -> void:
	if _player_id_notice != null and is_instance_valid(_player_id_notice):
		_player_id_notice.call("notice", key)


func _on_submenu_name_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_submenu_name_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_submenu_name_input.text)
		_submenu_name_input.accept_event()


func _on_submenu_addr_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_submenu_addr_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_submenu_addr_input.text)
		_submenu_addr_input.accept_event()


func _on_submenu_backdrop_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		_close_server_submenu()


func mouse_on_lan() -> void:
	if _selected_mode != CoopPanelMode.LAN:
		SoundManager.play_sfx("ButtonSounds2")
		lan_option_player.play("on_select")


func mouse_out_lan() -> void:
	if _selected_mode != CoopPanelMode.LAN:
		lan_option_player.play_backwards("on_select")


func mouse_on_relay() -> void:
	if _selected_mode != CoopPanelMode.RELAY:
		SoundManager.play_sfx("ButtonSounds2")
		relay_option_player.play("on_select")


func mouse_out_relay() -> void:
	if _selected_mode != CoopPanelMode.RELAY:
		relay_option_player.play_backwards("on_select")


func mouse_on_option() -> void:
	if _selected_mode != CoopPanelMode.OPTION:
		SoundManager.play_sfx("ButtonSounds2")
		option_option_player.play("on_select")


func mouse_out_option() -> void:
	if _selected_mode != CoopPanelMode.OPTION:
		option_option_player.play_backwards("on_select")


# ---------------- LAN 页：房间标识地址类型（公网/局域网，互斥开关） ----------------

func _refresh_addr_mode() -> void:
	var coop = CoopNetScript.instance
	var mode: int = int(coop.get("room_address_mode")) if coop != null else 0
	_addr_lan_toggle.set_on(mode == 0, false)
	_addr_public_toggle.set_on(mode == 1, false)


func _on_lan_addr_toggled(on: bool) -> void:
	if on:
		_apply_addr_mode(0)
	else:
		# 不允许两个都关：忽略关闭，恢复选中
		_addr_lan_toggle.set_on(true)


func _on_public_addr_toggled(on: bool) -> void:
	if not on:
		# 不允许两个都关：忽略关闭，恢复选中
		_addr_public_toggle.set_on(true)
		return
	# 选中公网即保持（不再因暂无公网地址而回退到局域网）
	_apply_addr_mode(1)


# 应用地址类型：始终保持用户所选，不因暂无公网地址而回退（提示由 set_room_address_mode 负责）
func _apply_addr_mode(mode: int) -> void:
	var coop = CoopNetScript.instance
	if coop != null:
		coop.call("set_room_address_mode", mode)
	_addr_lan_toggle.set_on(mode == 0)
	_addr_public_toggle.set_on(mode == 1)


# ---------------- LAN 页：手动公网 IP ----------------

func _refresh_manual_ip() -> void:
	var coop = CoopNetScript.instance
	var text: String = ""
	if coop != null:
		text = str(coop.get("manual_public_ip"))
	if _public_ip_input != null and _public_ip_input.text != text:
		_public_ip_input.text = text


func _submit_manual_ip() -> void:
	var coop = CoopNetScript.instance
	if coop == null or _public_ip_input == null:
		return
	var text: String = _public_ip_input.text.strip_edges()
	var ok: bool = bool(coop.call("set_manual_public_ip", _public_ip_input.text))
	if not ok:
		# 非法输入：回填当前有效值
		_refresh_manual_ip()
		if _player_id_notice != null and is_instance_valid(_player_id_notice):
			_player_id_notice.call("notice", "coop_manual_ip_invalid")
		return
	# A：手填非空公网 IP 且当前为局域网 → 自动切到公网，房间标识立即用它
	if text != "" and int(coop.get("room_address_mode")) == 0:
		_apply_addr_mode(1)


func _on_public_ip_submitted(_text: String) -> void:
	_submit_manual_ip()


func _on_public_ip_focus_exited() -> void:
	_submit_manual_ip()


func _on_public_ip_clear_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop != null:
		coop.call("clear_manual_public_ip")
	if _public_ip_input != null:
		_public_ip_input.text = ""


func _on_public_ip_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_public_ip_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_public_ip_input.text)
		_public_ip_input.accept_event()


# UPnP 自动映射失败且未手填时，显示「请手动填入公网 IP」提示
func _refresh_manual_ip_hint(coop) -> void:
	if _manual_ip_hint == null:
		return
	var show: bool = false
	if coop != null and is_instance_valid(coop) and bool(coop.is_lan_game) and bool(coop.call("is_upnp_enabled")):
		var status: String = str(coop.get("upnp_status"))
		var manual: String = str(coop.get("manual_public_ip"))
		if (status == "no_gateway" or status == "map_failed") and manual == "":
			show = true
	if _manual_ip_hint.visible != show:
		_manual_ip_hint.visible = show


# ---------------- OPTION 页：玩家 ID ----------------

func _refresh_player_id_input() -> void:
	var coop = CoopNetScript.instance
	var name_text: String = ""
	if coop != null:
		var s = coop.get("settings")
		if s != null:
			name_text = str(s.get("player_id"))
	_player_id_input.text = name_text


func _on_player_id_confirm_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_submit_player_id()


func _on_player_id_text_submitted(_text: String) -> void:
	_submit_player_id()


# 按「确定」/回车：>12 字符拒绝保存并提示；否则保存并提示已保存。
func _submit_player_id() -> void:
	var coop = CoopNetScript.instance
	if coop == null:
		return
	var ok: bool = bool(coop.call("set_local_display_name", _player_id_input.text))
	if _player_id_notice != null and is_instance_valid(_player_id_notice):
		_player_id_notice.call("notice", "coop_player_id_saved" if ok else "coop_player_id_too_long")


func _on_player_id_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_player_id_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_player_id_input.text)
		_player_id_input.accept_event()


func _on_player_id_confirm_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_player_id_confirm_pressed()
		_player_id_confirm.accept_event()


func _on_host_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_host_pressed()
		_host_button.accept_event()


func _on_join_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_join_pressed()
		_join_button.accept_event()


func _on_ip_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_ip_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_ip_input.text)
		_ip_input.accept_event()


func _on_port_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_port_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_port_input.text)
		_port_input.accept_event()


func _on_relay_server_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_relay_server_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_relay_server_input.text)
		_relay_server_input.accept_event()


func _on_relay_room_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_relay_room_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_relay_room_input.text)
		_relay_room_input.accept_event()


func _on_relay_create_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_relay_create_pressed()
		_relay_create_button.accept_event()


func _on_relay_join_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_relay_join_pressed()
		_relay_join_button.accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _selected_mode == CoopPanelMode.EXTENSION:
		_refresh_extension_status.call_deferred()


func _on_extension_state_changed(id: String, state: String, message: String) -> void:
	var previous: Dictionary = _extension_statuses.get(id, {})
	_extension_statuses[id] = {"state": state, "message": message,
		"network": previous.get("network", "") if state == "ready" else ""}
	if state in ["preparing", "ready"]:
		_active_extension_status = id
	elif _active_extension_status == id:
		_active_extension_status = ""
	if _selected_mode == CoopPanelMode.EXTENSION and _selected_extension == id:
		_refresh_extension_status()


func _refresh_extension_status() -> void:
	var status: Dictionary = _extension_statuses.get(_selected_extension, {})
	var message: String = str(status.get("message", ""))
	match str(status.get("state", "idle")):
		"preparing":
			message = "coop_status_extension_preparing"
		"ready":
			message = str(status.get("network", ""))
			if message.is_empty() or message == "offline":
				message = "coop_status_extension_ready"
		"failed":
			if message.is_empty():
				message = "coop_status_extension_failed"
		_:
			message = "offline"
	_set_status(message, _extension_pages[_selected_extension].title)
	if status.get("state") == "failed":
		_status_dot.color = Color(0.95, 0.18, 0.12)
	elif message in ["coop_status_extension_preparing", "coop_status_extension_ready"]:
		_status_dot.color = Color(1.0, 0.78, 0.12)


func _on_connection_status_changed(message: String) -> void:
	# 只有当前组网会话接收网络状态；失败/取消后的迟到通知不能覆盖已缓存的结果。
	if not _active_extension_status.is_empty():
		_extension_statuses[_active_extension_status]["network"] = message
	if _selected_mode == CoopPanelMode.EXTENSION:
		_refresh_extension_status()
	elif _selected_mode == CoopPanelMode.RELAY:
		_set_status(message, "RELAY")
	elif _selected_mode == CoopPanelMode.DEDICATED:
		return
	else:
		_lan_status_message = message
		_set_status(message, "LAN")
	var coop = CoopNetScript.instance
	if coop != null:
		# 连接进行中锁定 / 握手完成或失败后解锁，避免重复点击被中继当作新成员排序
		_set_relay_busy(coop.is_connect_in_flight())
	if coop != null and coop.relay_room_code != "":
		_relay_room_code_label.text = tr("coop_room_code_value") % coop.relay_room_code
	if message.begins_with("Hosting"):
		_update_local_ip_label(message)


func _set_status(message: String, prefix: String = "LAN") -> void:
	var lower := message.to_lower()
	var color := OFFLINE_COLOR
	if lower.contains("failed") or lower.contains("disconnected") or lower.contains("not available"):
		color = DANGER_COLOR
	elif lower.contains("connected") or lower.contains("joined") or lower.contains("selected") or lower.contains("created"):
		color = OK_COLOR
	elif lower.contains("hosting") or lower.contains("joining") or lower.contains("waiting") or lower.contains("creating"):
		color = WARN_COLOR
	if _status_label != null:
		_status_label.text = tr("coop_status_format") % [_localize_status_prefix(prefix), _localize_status_message(message)]
		_status_label.add_theme_color_override("font_color", color)
	if _status_dot != null:
		_status_dot.color = color


func _update_local_ip_label(host_message: String = "") -> void:
	if _local_ip_label == null:
		return
	var coop = CoopNetScript.instance
	var address_text := host_message
	if address_text.begins_with("Hosting "):
		address_text = address_text.trim_prefix("Hosting ")
	# 已 UPnP 映射：优先显示公网地址（客机填这个直连）
	var ext: String = str(coop.get("external_address")) if coop != null else ""
	if ext != "":
		var port: int = int(coop.call("get_lan_port"))
		_local_ip_label.text = tr("coop_public_ip_format") % ("%s:%d" % [ext, port])
		return
	var displayed := address_text if address_text != "" else _get_local_ip_summary()
	_local_ip_label.text = tr("coop_your_ip_format") % displayed


func _get_local_ip_summary() -> String:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		var summary: String = str(coop.call("get_local_lan_ip_summary"))
		if summary != "":
			return summary
	return tr("coop_unavailable")


func _localize_status_prefix(prefix: String) -> String:
	match prefix:
		"LAN":
			return tr("coop_mode_lan")
		"RELAY":
			return tr("coop_mode_relay")
		"DEDICATED":
			return tr("coop_mode_dedicated")
		_:
			return prefix


func _localize_status_message(message: String) -> String:
	if message.begins_with("coop_status_"):
		return tr(message)
	var exact := {
		"offline": "coop_status_offline",
		"Host failed": "coop_status_host_failed",
		"Join failed": "coop_status_join_failed",
		"Creating relay room": "coop_status_creating_relay_room",
		"Only host can start a LAN run": "coop_status_only_host_start",
		"Waiting for all players to select": "coop_status_waiting_for_players",
		"Connected to relay": "coop_status_connected_relay",
		"Connected to host": "coop_status_connected_host",
		"Connection failed": "coop_status_connection_failed",
		"Relay disconnected": "coop_status_relay_disconnected",
		"Server disconnected": "coop_status_server_disconnected",
	}
	if exact.has(message):
		return tr(exact[message])
	if message.begins_with("Relay room ") and message.ends_with(" created"):
		return tr("coop_status_relay_room_created") % message.trim_prefix("Relay room ").trim_suffix(" created")
	if message.begins_with("Peer ") and message.ends_with(" joined"):
		return tr("coop_status_peer_joined") % message.trim_prefix("Peer ").trim_suffix(" joined")
	if message.begins_with("Peer ") and message.ends_with(" left"):
		return tr("coop_status_peer_left") % message.trim_prefix("Peer ").trim_suffix(" left")
	var prefixes := {
		"Host failed: ": "coop_status_host_failed_detail",
		"Join failed: ": "coop_status_join_failed_detail",
		"Hosting LAN on port ": "coop_status_hosting_lan_port",
		"Hosting ": "coop_status_hosting_address",
		"Joining relay room ": "coop_status_joining_relay_room",
		"Joining ": "coop_status_joining_address",
		"Joined relay as peer ": "coop_status_joined_relay_peer",
		"Relay failed: ": "coop_status_relay_failed_detail",
	}
	for source_prefix in prefixes:
		if message.begins_with(source_prefix):
			return tr(prefixes[source_prefix]) % message.trim_prefix(source_prefix)
	return message

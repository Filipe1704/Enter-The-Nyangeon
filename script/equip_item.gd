class_name EquipItem
extends Node2D

# 道具通用基类
# 子类只需实现 _apply_effect(quantity)，可选实现 _on_equip / _setup，
# 以及用 attach_rail_icon / attach_hat_icon / attach_muzzle_icon / attach_follow_icon 挂载图标。

var item_id: String
var num: int = 0

# 跟随图标节点的归属标记：值=拥有者玩家节点（用于续链与排除联机镜像，见 attach_follow_icon）。
const FOLLOW_OWNER_META := "follow_owner"
# follow 挂点的占用字段（其余三类是嵌套挂点：hat_use / picatinny_rail_use / muzzle_use）。
const FOLLOW_FIELD := "follow_use"

# 本道具挂到玩家挂点上的图标（跟随/帽子/导轨/枪口）及其挂点类型字段：
# 道具释放时一并回收并释放挂点，否则测试房重置等「道具被清、玩家保留」的路径会留下
# 旧图标、且玩家自带挂点的 *_use 永远为 true，下一轮第一件同类道具就挂不上。
# 每项为 {icon, marker, field, owner}：
# - 释放时优先用运行时宿主（icon.get_parent() / follow_mark），因为上游道具释放可能已把
#   下游图标上提到别的挂点；marker 只作为「图标已被外部提前释放」时的兜底。
# - owner 用于 follow 链重建：图标被外部清掉后仍能找回本玩家（_exit_tree 里 player 为 null）。
var _attached_icons: Array[Dictionary] = []

# 玩家引用：跨帧自动刷新，避免长期缓存换角色后已释放的实例（见 PlayerRef）。
# 子类直接读写 `player` 即可，无需自己重新解析；子类不得再声明 `var player`（会与基类成员冲突）。
var _player: Node
var player: Node:
	get:
		_player = PlayerRef.ensure(self, _player)
		return _player
	set(value):
		_player = value

func _ready() -> void:
	item_id = _get_item_id()
	_on_equip()
	_apply_effect(1)
	_setup()
	GameEvents.ability_upgrade_added.connect(_on_upgrade_added)
	PlayerData.update_player_ability()

func _exit_tree() -> void:
	_clear_attached_icons()

# 回收本道具挂出的图标并释放挂点。
#
# 释放时机不一定是「整批清道具」，所以这里做释放期自愈：
#   1) 先给 follow 链拍快照（玩家.Follow ← icon1.Follow ← icon2.Follow ← …）；
#   2) 倒序释放（后挂的先拆）：嵌套挂点（Hat/Rail/Muzzle）把下游图标上提给自己的宿主，
#      避免「移除上游道具 → 下游图标作为后代被连带释放」；
#   3) 最后按快照重建 follow 链：断链的存活图标重新串回玩家挂点，不留在原地冻结。
# 宿主一律运行时现取：嵌套用 icon.get_parent()，follow 用 icon.follow_mark。
func _clear_attached_icons() -> void:
	if _attached_icons.is_empty():
		return
	var follow_owner: Node = null
	for entry in _attached_icons:
		if str(entry.get("field")) != FOLLOW_FIELD:
			continue
		var owner = entry.get("owner")
		if is_instance_valid(owner):
			follow_owner = owner
			break
		var cached_icon = entry.get("icon")
		if is_instance_valid(cached_icon) and cached_icon.has_meta(FOLLOW_OWNER_META):
			follow_owner = cached_icon.get_meta(FOLLOW_OWNER_META)
			break
	var follow_chain: Array = []
	if follow_owner != null and is_instance_valid(follow_owner):
		follow_chain = _collect_follow_chain(follow_owner)
	var released: Array = []
	for i in range(_attached_icons.size() - 1, -1, -1):
		var entry: Dictionary = _attached_icons[i]
		var icon = entry.get("icon")
		var field := str(entry.get("field"))
		if not is_instance_valid(icon):
			# 图标已被外部提前释放（如 reset_clear_unit 先清 PlayerRoot）：只做挂点兜底复位；
			# follow 的挂点由下面的链重建统一复位。
			if field != FOLLOW_FIELD:
				var stale_marker = entry.get("marker")
				if stale_marker != null and is_instance_valid(stale_marker):
					_release_marker_if_empty(stale_marker, field, null)
			continue
		if icon.is_queued_for_deletion():
			continue
		if field == FOLLOW_FIELD:
			released.append(icon)
			icon.queue_free()
			continue
		var host = icon.get_parent()
		_hoist_descendants(icon, field, host)
		icon.queue_free()
		_release_marker_if_empty(host, field, icon)
	_attached_icons.clear()
	if follow_owner != null and is_instance_valid(follow_owner):
		_rebuild_follow_chain(follow_owner, follow_chain, released)

func _track_icon(icon: Node, marker: Node, use_field: String, owner: Node) -> Node:
	_attached_icons.append({"icon": icon, "marker": marker, "field": use_field, "owner": owner})
	return icon

# ---------------- 释放期自愈：单项移除时保持挂点链完整 ----------------

# owner 拥有（本体道具生成）的 follow 图标：以 follow_owner meta 为准，排除联机镜像。
# 图标与玩家同为 PlayerRoot 的子节点，所以直接用 owner.get_parent()；
# _exit_tree 里不能用 get_tree()/全局组（离树后 get_tree() 为 null）。
func _owned_follow_icons(owner: Node) -> Array:
	var icons: Array = []
	var player_root := owner.get_parent()
	if player_root == null:
		return icons
	for child in player_root.get_children():
		if not is_instance_valid(child):
			continue
		if not child.has_meta(FOLLOW_OWNER_META):
			continue
		if child.get_meta(FOLLOW_OWNER_META) != owner:
			continue
		if child.has_method("get_follow"):
			icons.append(child)
	return icons

# 玩家自带的 Follow 挂点（玩家子树内；图标内置的不算）。
func _player_follow_markers(owner: Node) -> Array:
	var markers: Array = []
	if owner.is_in_group("Follow"):
		markers.append(owner)
	for node in owner.find_children("*", "", true, false):
		if node.is_in_group("Follow"):
			markers.append(node)
	return markers

# 按链序快照：从玩家自带 Follow 沿 follow_mark 往下走；已断链的孤儿追加到末尾待重连。
func _collect_follow_chain(owner: Node) -> Array:
	var ordered: Array = []
	if not owner.is_inside_tree():
		return ordered
	var by_marker: Dictionary = {}
	for icon in _owned_follow_icons(owner):
		var mark = icon.get("follow_mark")
		if mark != null and is_instance_valid(mark):
			by_marker[mark] = icon
	var player_markers := _player_follow_markers(owner)
	var marker: Node = player_markers[0] if player_markers.size() > 0 else null
	var guard := 0
	while marker != null and by_marker.has(marker) and guard < 128:
		var icon = by_marker[marker]
		ordered.append(icon)
		by_marker.erase(marker)
		marker = icon.get_node_or_null("Follow")
		guard += 1
	for orphan in by_marker.values():
		ordered.append(orphan)
	return ordered

# 按快照把存活图标重新串成一条链，并复位所有不再被占用的 follow 挂点。
func _rebuild_follow_chain(owner: Node, ordered: Array, released: Array) -> void:
	if not owner.is_inside_tree() or owner.is_queued_for_deletion():
		return
	var survivors: Array = []
	for icon in ordered:
		if not is_instance_valid(icon) or icon.is_queued_for_deletion():
			continue
		if released.has(icon):
			continue
		survivors.append(icon)
	var player_markers := _player_follow_markers(owner)
	var markers: Array = player_markers.duplicate()
	for icon in survivors:
		var inner = icon.get_node_or_null("Follow")
		if inner != null:
			markers.append(inner)
	for marker in markers:
		if is_instance_valid(marker) and not marker.is_queued_for_deletion() and marker.get(FOLLOW_FIELD) == true:
			marker.set(FOLLOW_FIELD, false)
	if survivors.is_empty() or player_markers.is_empty():
		return
	var tail: Node = player_markers[0]
	for icon in survivors:
		if not is_instance_valid(icon) or icon.is_queued_for_deletion():
			continue
		icon.call("get_follow", tail)
		tail.set(FOLLOW_FIELD, true)
		var next = icon.get_node_or_null("Follow")
		if next == null:
			break
		tail = next

# 嵌套挂点（Hat/Rail/Muzzle）：释放本图标前，把它内嵌挂点下的下游图标上提到本图标的宿主，
# 这样移除上游道具不会连带删掉后面道具的图标（保持局部变换，视觉位置不跳）。
# 对象参数故意不写类型：可能收到已释放实例，带类型的形参会先于 is_instance_valid 抛错。
func _hoist_descendants(icon, field: String, host) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_inside_tree() or not icon.is_inside_tree():
		return
	for child in icon.get_children():
		if child.get(field) == null:
			continue
		for downstream in child.get_children():
			if not is_instance_valid(downstream) or downstream.get_parent() != child:
				continue
			downstream.reparent(host, false)

# 释放后复位挂点：除自己与已 queue 的节点外没有其它占用者才置 false（被上提的图标仍算占用）。
# 对象参数同样不写类型，允许传入已释放实例/上游 marker。
func _release_marker_if_empty(host, field: String, released_icon) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if host.get(field) != true:
		return
	for child in host.get_children():
		if child == released_icon:
			continue
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			return
	host.set(field, false)

# 默认按场景文件名推导道具 id（upgrade_manager 以 res://scenes/update_item/<id>.tscn 加载）
# 如需写死可覆盖此函数返回字符串。
func _get_item_id() -> String:
	var path := get_scene_file_path()
	if path != "":
		return path.get_file().get_basename()
	return name

func _on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary) -> void:
	if upgrade.id != item_id:
		return
	if current_upgrade[item_id]["quantity"] == 1:
		return
	num = current_upgrade[item_id]["quantity"]
	_apply_effect(num)
	PlayerData.update_player_ability()

# 首次获取时的一次性初始化：生成 body、挂载图标、连接额外信号等
func _on_equip() -> void:
	pass

# 额外的信号连接钩子（在 _on_equip 与首次 _apply_effect 之后调用）
func _setup() -> void:
	pass

# 属性/效果应用：首次以 quantity = 1 调用，之后每次叠加以当前数量调用
func _apply_effect(_quantity: int) -> void:
	pass

# 挂载图标到枪械导轨（占用本玩家第一个空闲 Rail）
# 图标本身就是导轨挂点的子节点，所以「玩家子树」判定即可覆盖续链（图标内嵌 Rail 仍在玩家下）。
func attach_rail_icon(icon_scene: PackedScene) -> bool:
	var local_player := player
	if local_player == null:
		return false
	for rail in get_tree().get_nodes_in_group("Rail"):
		# 联机镜像的 Rail 同样留在全局组里；只占用本玩家（含已挂图标内嵌 Rail）的挂点。
		if not local_player.is_ancestor_of(rail):
			continue
		if rail.get("picatinny_rail_use") == false:
			var icon := icon_scene.instantiate()
			rail.add_child(icon)
			rail.set("picatinny_rail_use", true)
			_track_icon(icon, rail, "picatinny_rail_use", local_player)
			return true
	return false

# 挂载图标到头部挂点（占用本玩家第一个空闲 Hat）
func attach_hat_icon(icon_scene: PackedScene) -> bool:
	var local_player := player
	if local_player == null:
		return false
	for hat in get_tree().get_nodes_in_group("Hat"):
		if not local_player.is_ancestor_of(hat):
			continue
		if hat.get("hat_use") == false:
			var icon := icon_scene.instantiate()
			hat.add_child(icon)
			hat.set("hat_use", true)
			_track_icon(icon, hat, "hat_use", local_player)
			return true
	return false

# 挂载图标到枪口挂点（占用本玩家第一个空闲 Muzzle）
func attach_muzzle_icon(icon_scene: PackedScene) -> bool:
	var local_player := player
	if local_player == null:
		return false
	for muzzle in get_tree().get_nodes_in_group("Muzzle"):
		if not local_player.is_ancestor_of(muzzle):
			continue
		if muzzle.get("muzzle_use") == false:
			var icon := icon_scene.instantiate()
			muzzle.add_child(icon)
			muzzle.set("muzzle_use", true)
			_track_icon(icon, muzzle, "muzzle_use", local_player)
			return true
	return false

# 挂载图标到跟随点（占用道具拥有者链条上的第一个空闲 Follow），返回图标节点，失败返回 null。
#
# 多件跟随道具是**链表**：玩家场景自带 1 个 Follow，每个 <id>_icon.tscn 内置 1 个 Follow，
# 所以链条为「玩家.Follow ← icon1.Follow ← icon2.Follow ← …」。联机镜像的 Follow 也会留在
# 全局组里，必须排除，但不能只用 is_ancestor_of —— 图标挂在 PlayerRoot 下，其内置 Follow
# 不在玩家子树内，那样会把链切断（第二件起静默不生成，见 docs/LEARNINGS.md）。
func attach_follow_icon(icon_scene: PackedScene) -> Node:
	var local_player := player
	if local_player == null:
		return null
	var player_root := get_tree().get_first_node_in_group("PlayerRoot")
	if player_root == null:
		push_warning("attach_follow_icon: 找不到 PlayerRoot（%s）" % item_id)
		return null
	for follow in get_tree().get_nodes_in_group("Follow"):
		if not _follow_owned_by(follow, local_player):
			continue
		if follow.get("follow_use") == false:
			var icon := icon_scene.instantiate()
			# 图标内置 Follow 是同一玩家后续图标的挂点：记录归属以便续链。
			icon.set_meta(FOLLOW_OWNER_META, local_player)
			player_root.add_child(icon)
			icon.call("get_follow", follow)
			follow.set("follow_use", true)
			_track_icon(icon, follow, FOLLOW_FIELD, local_player)
			return icon
	push_warning("attach_follow_icon: 本玩家无可占用 Follow 挂点（%s）" % item_id)
	return null

# 挂点归属：玩家自身子树内的挂点，或已挂在本玩家图标链上的图标内置挂点。
func _follow_owned_by(follow: Node, local_player: Node) -> bool:
	if local_player.is_ancestor_of(follow):
		return true
	var node := follow.get_parent()
	while node != null and not node.is_in_group("PlayerRoot"):
		if node.has_meta(FOLLOW_OWNER_META):
			var owner = node.get_meta(FOLLOW_OWNER_META)
			return is_instance_valid(owner) and owner == local_player
		node = node.get_parent()
	return false

class_name EquipItem
extends Node2D

# 道具通用基类
# 子类只需实现 _apply_effect(quantity)，可选实现 _on_equip / _setup，
# 以及用 attach_rail_icon / attach_hat_icon / attach_muzzle_icon / attach_follow_icon 挂载图标。

var item_id: String
var num: int = 0

# 跟随图标节点的归属标记：值=拥有者玩家节点（用于续链与排除联机镜像，见 attach_follow_icon）。
const FOLLOW_OWNER_META := "follow_owner"

# 本道具挂到玩家挂点上的图标（跟随/帽子/导轨/枪口）及其占用的挂点：
# 道具释放时一并回收并释放挂点，否则测试房重置等「道具被清、玩家保留」的路径会留下
# 旧图标、且玩家自带挂点的 *_use 永远为 true，下一轮第一件同类道具就挂不上。
# 每项为 {icon, marker, field}。
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

# 回收本道具挂出的图标并释放挂点；图标之间可能嵌套成链，逐个 is_instance_valid 守卫。
func _clear_attached_icons() -> void:
	for entry in _attached_icons:
		var marker = entry.get("marker")
		if is_instance_valid(marker) and marker.get(entry.get("field")) == true:
			marker.set(entry.get("field"), false)
		var icon = entry.get("icon")
		if is_instance_valid(icon) and not icon.is_queued_for_deletion():
			icon.queue_free()
	_attached_icons.clear()

func _track_icon(icon: Node, marker: Node, use_field: String) -> Node:
	_attached_icons.append({"icon": icon, "marker": marker, "field": use_field})
	return icon

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
			_track_icon(icon, rail, "picatinny_rail_use")
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
			_track_icon(icon, hat, "hat_use")
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
			_track_icon(icon, muzzle, "muzzle_use")
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
			_track_icon(icon, follow, "follow_use")
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

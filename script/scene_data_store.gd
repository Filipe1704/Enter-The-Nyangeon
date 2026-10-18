extends RefCounted

## 存档文件事务：临时文件完成后直接替换主路径；只备份已验证的主档。
## can_save 在读取结束前及双坏档/未来版本下为 false，避免自动保存破坏证据。
const PRIMARY := "user://PlayerData.res"
const BACKUP := "user://PlayerData.res.bak"
const TEMP := "user://PlayerData_new.res"
const BACKUP_TEMP := "user://PlayerData.res.bak.new"
const RECOVERY := "user://PlayerData_recovery.res"

var can_save := false
var recovered := false
var _future_format_seen := false

# 仅在读旧存档期间接管明确缺失的 Mod Resource；不改变全局缺资源策略。
# 占位对象保持 ext_resource 的共享身份，Game 迁移时用支援字典 key 恢复 ID。
class LegacySupportLoader extends ResourceFormatLoader:
	var placeholders: Dictionary = {}
	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["tres", "res"])
	func _handles_type(type: StringName) -> bool:
		return type in [&"", &"Resource", &"SupportCard"]
	func _recognize_path(path: String, _type: StringName) -> bool:
		return placeholders.has(path)
	func _exists(path: String) -> bool:
		return placeholders.has(path)
	func _get_resource_type(path: String) -> String:
		return "Resource" if placeholders.has(path) else ""
	func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int):
		return placeholders.get(path, ERR_FILE_NOT_FOUND)

func load_data() -> SceneData:
	can_save = false
	recovered = false
	_future_format_seen = false
	var data := _read(PRIMARY)
	if _future_format_seen:
		push_warning("存档来自更新版本，已暂停保存以避免降级覆盖")
		return null
	if data != null:
		can_save = true
		return data
	if FileAccess.file_exists(BACKUP):
		# ResourceLoader 按扩展名选择加载器，.bak 须复制到独立 .res 读取。
		if DirAccess.copy_absolute(BACKUP, RECOVERY) == OK:
			data = _read(RECOVERY)
			DirAccess.remove_absolute(RECOVERY)
		if data != null:
			can_save = true
			recovered = true
			return data
	# 首次启动允许创建新档；任何现存坏档均保留，等待显式恢复。
	can_save = not FileAccess.file_exists(PRIMARY) and not FileAccess.file_exists(BACKUP)
	if not can_save:
		push_warning("存档及备份无法恢复，已暂停自动保存并保留原文件")
	return null

func save_data(data: SceneData) -> bool:
	if not can_save or data == null or data.save_version < 0 or data.save_version > SceneData.SAVE_VERSION:
		return false
	_future_format_seen = false
	var previous := _read(PRIMARY)
	if _future_format_seen:
		can_save = false
		push_warning("主档已由更新版本写入，已暂停保存")
		return false
	var err := ResourceSaver.save(data, TEMP)
	if err != OK:
		push_warning("写入临时存档失败 (error %d)，原存档未替换" % err)
		return false
	# 原子替换前保留已验证的主档；坏主档绝不能覆盖有效备份。
	if previous != null:
		err = DirAccess.copy_absolute(PRIMARY, BACKUP_TEMP)
		if err == OK:
			err = _replace(BACKUP_TEMP, BACKUP)
		if err != OK:
			push_warning("备份存档失败 (error %d)，原存档未替换" % err)
			return false
	err = _replace(TEMP, PRIMARY)
	if err != OK:
		push_warning("替换存档失败 (error %d)，原存档与备份均保留" % err)
		return false
	recovered = false
	return true

func _replace(source: String, destination: String) -> Error:
	# 同目录 rename 覆盖文件：失败时不先移走/删除 destination。
	return DirAccess.rename_absolute(source, destination)

func _read(path: String) -> SceneData:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var magic := file.get_buffer(4).get_string_from_ascii()
	file.close()
	if magic not in ["RSRC", "RSCC"]:
		return null
	var legacy_loader := LegacySupportLoader.new()
	for dependency in ResourceLoader.get_dependencies(path):
		var parts := dependency.split("::")
		var external: String = parts[2] if parts.size() > 2 else parts[0]
		if external.begins_with("res://mods/") and external.get_extension() in ["tres", "res"] \
				and not ResourceLoader.exists(external):
			legacy_loader.placeholders[external] = SupportCard.new()
	if not legacy_loader.placeholders.is_empty():
		ResourceLoader.add_resource_format_loader(legacy_loader, true)
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SceneData
	if not legacy_loader.placeholders.is_empty():
		ResourceLoader.remove_resource_format_loader(legacy_loader)
	if data != null and data.save_version > SceneData.SAVE_VERSION:
		_future_format_seen = true
		return null
	if data == null or data.save_version < 0:
		return null
	return data

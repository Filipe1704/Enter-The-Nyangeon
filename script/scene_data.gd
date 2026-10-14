extends Resource
class_name SceneData

# 存档结构版本。默认 0（而非当前值）是为了让旧档（无 save_version 字段）加载后
# 解析为 0，从而能被 load_playerdata 的路由识别为旧格式并迁移；新档在 save_playerdata
# 里显式写入当前值。每改一次序列化字段结构就 +1，并在 Game._migrate_scene_data 补迁移。
const SAVE_VERSION := 3

@export var save_version: int = 0
@export var player_pyroxenes: int
@export var character: Array
@export var group: Array
@export var clothes_group: Dictionary
@export var now_clothes: Dictionary
@export var game_mode: Array
@export var support_savedata: Dictionary
# v3 只保存选择 ID；旧字段保留用于 v0-v2 迁移，新写入必须为 null。
@export var game_support_id: String = "null"
@export var game_support: SupportCard

static func support_progress(entries: Dictionary) -> Dictionary:
	var result := {}
	for id in entries:
		var entry = entries[id]
		if id is String and entry is Dictionary:
			result[id] = {"LV": int(entry.get("LV", 1)), "exp": int(entry.get("exp", 0))}
	return result

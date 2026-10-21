extends Resource
class_name GameMode

const HAVOC_ID := "havoc"

@export var game_mode_name: String
@export var game_mode_id: String
@export var game_mode_icon: Texture2D
@export var gamemode_conflicting: Array[String]

@export_category("Chip")
@export var chip_enabled: bool = false
@export var chip_weight: float = 1.0
@export var chip_include_boss: bool = false
@export var chip_target_enemy_ids: Array[String] = []
@export var chip_target_tags: Array[String] = []
@export var chip_buffs: Array[Buff] = []

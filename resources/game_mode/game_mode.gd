extends Resource
class_name GameMode

const HAVOC_ID := "havoc"

enum ChipKind { ENEMY, FIELD, PLAYER }

@export var game_mode_name: String
@export var game_mode_id: String
@export var game_mode_icon: Texture2D
@export var gamemode_conflicting: Array[String]

@export_category("Chip")
@export var chip_enabled: bool = false
@export var chip_kind: ChipKind = ChipKind.ENEMY
@export var chip_weight: float = 1.0
@export var chip_include_boss: bool = false
@export var chip_target_enemy_ids: Array[String] = []
@export var chip_target_tags: Array[String] = []
@export var chip_buffs: Array[Buff] = []

@export_group("Player Chip")
@export var chip_player_buffs: Array[Buff] = []

@export_group("Field Chip")
@export var chip_field_scene: PackedScene

func is_enemy_chip() -> bool:
	return chip_kind == ChipKind.ENEMY

func is_field_chip() -> bool:
	return chip_kind == ChipKind.FIELD

func is_player_chip() -> bool:
	return chip_kind == ChipKind.PLAYER

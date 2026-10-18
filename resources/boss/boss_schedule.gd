extends Resource
class_name BossSchedule

# 一局使用的 Boss 编排表。fixed 与 endless 分开，避免无尽模式误用普通回合条目。
enum EndlessMode {
	ROTATION,
	WEIGHTED,
}

@export var id: String = ""
@export var priority: int = 0
@export var entries: Array[BossEncounterEntry] = []
@export var endless_entries: Array[BossEncounterEntry] = []
@export var endless_mode: EndlessMode = EndlessMode.ROTATION
@export var enabled: bool = true

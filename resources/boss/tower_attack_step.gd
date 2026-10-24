extends Resource
class_name TowerAttackStep

# 侵蚀之塔单次「出招」配置。窗口/间隔单位均为 0.1s tick（GameEvents.global_time_count）。
# tower_types 对应子塔导出的 tower_type：1=激光 2=弹幕 3=召唤（见 erosion_tower_group.tscn）。
@export var label: String = ""
@export var tower_types: Array[int] = [1]
# 基准攻击窗口；激光塔参战时实际窗口会被 launcher 的 total_active_ticks() 抬升。
@export var window_ticks: int = 180
# 本招收招后到下一招的间隔。
@export var gap_ticks: int = 25
# 生效阶段位掩码（阶段由 erosion_tower_group.phase_hp_thresholds 计算）。
@export_flags("阶段1", "阶段2", "阶段3", "阶段4") var phases: int = 1

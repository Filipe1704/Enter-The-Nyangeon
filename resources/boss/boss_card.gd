extends EnemyCard
class_name BossCard

# Boss 的内容定义。继承 EnemyCard 以复用现有 id/body/icon/刷怪链路；
# 具体动画仍由每个 Boss 场景自己的 AnimationPlayer 负责。
@export var boss_name_key: String = ""
# 无翻译键时显示的名字；通常留空，优先使用 boss_name_key。
@export var boss_name: String = ""
@export var round_profile: BossRoundProfile

@export var enter_anim_player_path: NodePath
@export var enter_anim_name: StringName = &"enter_anim"
@export var death_anim_player_path: NodePath
@export var death_anim_name: StringName = &"death_anim"
@export var escape_anim_name: StringName = &"escape_anim"
@export var camera_marker_path: NodePath

@export var bgm_intro: AudioStream
@export var bgm_loop: AudioStream
@export var reward_scene: PackedScene
@export var reward_coin_count: int = 0
@export var reward_coin_quantity: int = 100
@export var despawn_delay: float = 4.0

@export var phases: Array[BossPhase] = []
@export var cinematic: bool = true
@export var spawn_position: Vector2 = Vector2.ZERO
# 联机预留：远端镜像是否播放入场/死亡镜头（默认 false，只播动画）。
@export var network_remote_cinematic: bool = false

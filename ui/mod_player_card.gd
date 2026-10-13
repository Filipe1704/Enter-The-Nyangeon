extends "res://ui/player_card.gd"

# 通用 mod 选人卡：沿用原版 player_card 的节点树 / 动画 / 交互（保持一致的原版风格），
# 角色视觉（名字 / 武器 / 立绘 / 光环 / 配色）改由 PlayerCard 资源驱动。
# mod 未自带 card_scene 时，由 ui/mod_society_base.gd 实例化本卡作为兜底。

@onready var _halo_sprite: Sprite2D = $ColorRect/Node2D/Sprite2D
@onready var _bg_rect: ColorRect = $ColorRect2
@onready var _accent_rect: ColorRect = $ColorRect/Node2D/Node2D/ColorRect/ColorRect3


func _ready() -> void:
	# player_card 由 mod_society_base 在 add_child 前注入；缺失则无可显示内容。
	if player_card == null:
		return
	super._ready()
	_apply_generic_visual(player_card)


# branch_anim 的 method track 会调到这里；父类先刷新名字 / 武器 / 立绘 / PS，再补光环与配色。
func _update_visual() -> void:
	super._update_visual()
	_apply_generic_visual(cur if cur != null else player_card)


func _apply_generic_visual(card: PlayerCard) -> void:
	if card == null:
		return
	if name_label != null:
		name_label.text = str(card.name)
	if weapon_label != null:
		weapon_label.text = str(card.weapon)
	# 配色从 PlayerCard.color 派生；未设（默认黑 / 全透明）时回退中性灰。
	var tint: Color = card.color
	if tint.a <= 0.0 or tint.is_equal_approx(Color.BLACK):
		tint = Color(0.5, 0.5, 0.5)
	if _halo_sprite != null:
		_halo_sprite.texture = card.halo
		_halo_sprite.visible = card.halo != null
	if _bg_rect != null:
		_bg_rect.color = tint.lightened(0.25)
	if _accent_rect != null:
		_accent_rect.color = tint
	if weapon_label != null:
		weapon_label.add_theme_color_override("font_color", tint.darkened(0.35))

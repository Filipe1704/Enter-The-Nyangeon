extends "res://ui/mod_society_base.gd"

# 动态「MOD」通用社团卡：由 menu_screen / coop_select 按每页 4 个角色切片实例化，
# 每张承载 members（≤4）。可见性/填充（check_group / populate_player_cards）继承
# mod_society_base：任一成员未锁即显示，填充时跳过已锁成员。
# >4 个角色时消费方自动多建一张卡（MOD / MOD 2 / …）。


# 设置页码标签：单页显示 "MOD"，多页显示 "MOD <n>"。
func set_page(index: int, total: int) -> void:
	var lbl := get_node_or_null("Node2D/ColorRect/Label")
	if lbl != null:
		lbl.text = "MOD" if total <= 1 else "MOD %d" % (index + 1)


func mouse_select_anim() -> void:
	if on_select == false:
		SoundManager.play_sfx("ButtonSounds2")
		card_anim.play("select_anim")


func mouse_out_anim() -> void:
	if on_select == false:
		card_anim.play("out_anim")


func on_select_handle() -> void:
	on_select = true
	card_anim.play("on_select_anim")
	GameEvents.emit_society_card_selected(self)
	close_card()


func out_select_card() -> void:
	if on_select == true:
		on_select = false
		card_anim.play("out_select_anim")
		await get_tree().create_timer(0.3).timeout
		open_card()

class_name ShopPurchaseCard
extends PanelContainer

## 角色/服装商店的共用输入、确认动画与购买流程；商品数据和解锁由子类负责。
@onready var yes: PanelContainer = %Yes
@onready var no: PanelContainer = %No
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var yes_anim: AnimationPlayer = $Node2D3/Panel/TextureRect/Yes/YesAnim
@onready var no_anim: AnimationPlayer = $Node2D3/Panel/TextureRect/No/Node2D/NoAnim

var is_confirm: bool = false

func _ready() -> void:
	mouse_entered.connect(mouse_select)
	mouse_exited.connect(mouse_out)
	gui_input.connect(confirm_open)
	yes.mouse_entered.connect(yes_select)
	yes.mouse_exited.connect(yes_out)
	yes.gui_input.connect(yes_deal)
	no.mouse_entered.connect(no_select)
	no.mouse_exited.connect(no_out)
	no.gui_input.connect(no_deal)

func open_main_button():
	self.mouse_filter = 0

func close_main_button():
	self.mouse_filter = 2

func open_button():
	yes.mouse_filter = 0
	no.mouse_filter = 0

func close_button():
	yes.mouse_filter = 2
	no.mouse_filter = 2

func mouse_select():
	if is_confirm == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("select_anim")
		animation_player_2.play("select_anim")

func mouse_out():
	if is_confirm == false:
		animation_player.play("RESET")
		animation_player_2.play_backwards("select_anim")

func yes_select():
	SoundManager.play_sfx("ButtonSounds2")
	yes_anim.play("select_anim")

func yes_out():
	yes_anim.play_backwards("select_anim")

func yes_deal(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds2")
		close_button()
		yes_anim.play("select_anim")
		await yes_anim.animation_finished
		if _try_purchase():
			await _finish_purchase()
		else:
			yes_anim.play_backwards("select_anim")
			open_button()

	if event.is_action_pressed("shoot"):
		if _try_purchase():
			close_button()
			await _finish_purchase()

# 保留先解锁/通知、再读取当前价格扣款的顺序；货币 setter 负责随后的存档。
func _try_purchase() -> bool:
	if _get_purchase_cost() <= PlayerData.player_pyroxenes:
		_grant_purchase()
		PlayerData.player_pyroxenes -= _get_purchase_cost()
		SoundManager.play_sfx("CoinSounds")
		return true
	GameEvents.emit_pyroxenes_not_enough("Arona")
	return false

func _finish_purchase() -> void:
	animation_player_2.play_backwards("confirm_anim")
	await animation_player_2.animation_finished
	animation_player.play("RESET")
	animation_player_2.play_backwards("select_anim")
	await animation_player_2.animation_finished
	animation_player_2.play("deal_anim")

func _get_purchase_cost() -> int:
	return 0

func _grant_purchase() -> void:
	pass

func no_deal(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds2")
		close_button()
		no_anim.play("select_anim")
		await no_anim.animation_finished
		confirm_close()
		no_anim.play_backwards("select_anim")

	if event.is_action_pressed("shoot"):
		confirm_close()

func no_select():
	SoundManager.play_sfx("ButtonSounds2")
	no_anim.play("select_anim")

func no_out():
	no_anim.play_backwards("select_anim")

func confirm_open(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		if is_confirm == false:
			is_confirm = true
			SoundManager.play_sfx("ButtonSounds2")
			animation_player.play("select_anim")
			animation_player_2.play("select_anim")
			close_main_button()
			await animation_player_2.animation_finished
			animation_player_2.play("confirm_anim")
			await animation_player_2.animation_finished
			open_button()

	if event.is_action_pressed("shoot"):
		is_confirm = true
		SoundManager.play_sfx("ButtonSounds")
		animation_player_2.play("confirm_anim")
		close_main_button()
		await animation_player_2.animation_finished
		open_button()

func confirm_close():
	SoundManager.play_sfx("UISounds2")
	animation_player_2.play_backwards("confirm_anim")
	close_button()
	await animation_player_2.animation_finished
	is_confirm = false
	open_main_button()

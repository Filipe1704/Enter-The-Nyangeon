extends PanelContainer

@onready var item_icon = $Node2D/TextureRect
@onready var item_quantity: Label = $Node2D/Label

var card_id: String
var _tooltip: HoverTooltipBinding

func _ready() -> void:
	_tooltip = HoverTooltipBinding.bind(self, _tooltip_content, func(): return not card_id.is_empty())
	gui_input.connect(touch_show)
	GameEvents.ability_upgrade_added.connect(set_up_item_quantity)

func touch_show(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tooltip.preview("touch", event.index)

func _tooltip_content() -> Array:
	return [
		{"text": card_id + "_name", "role": "title"},
		{"text": card_id + "_description"},
		{"text": card_id + "_forward", "role": "positive"},
		{"text": card_id + "_negative", "role": "negative"},
	]

func set_up_item_card(upgrade: AbilityUpgrade) -> void:
	item_icon.texture = upgrade.icon
	card_id = upgrade.id
	_tooltip.refresh()

func set_up_item_quantity(upgrade: AbilityUpgrade, current_upgrade: Dictionary) -> void:
	if upgrade.id == card_id and current_upgrade[upgrade.id]["quantity"] > 1:
		item_quantity.text = str(current_upgrade[upgrade.id]["quantity"])

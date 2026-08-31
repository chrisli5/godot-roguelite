class_name UpgradeScreenUI
extends CanvasLayer

@export_group("Layout Configurations")
@export var card_scene: PackedScene

@onready var cards_container: HBoxContainer = $MarginContainer/HBoxContainer
@onready var reroll_button: Button = $MarginContainer/RerollButton


func _ready() -> void:
	# Keep user interface hidden from standard screen runtime frames by default
	hide()
	if is_instance_valid(reroll_button):
		reroll_button.pressed.connect(_on_reroll_button_pressed)
		
	# Automatically self-intercept selection notifications to clear view frames
	EventBus.upgrade_options_ready.connect(_on_upgrade_options_presented)
	EventBus.upgrade_selected.connect(_on_choice_finalized)


func _on_upgrade_options_presented(options: Array[UpgradeChoice]) -> void:
	if not is_instance_valid(cards_container) or not is_instance_valid(card_scene):
		return
		
	# Clear out old card frames from previous level-up cycles
	for child in cards_container.get_children():
		child.queue_free()
		
	# Populate screen with newly drawn card choice options
	for choice in options:
		var card_instance = card_scene.instantiate()
		if card_instance is UpgradeCard:
			cards_container.add_child(card_instance)
			card_instance.populate_display_data(choice)

	show()

func _on_choice_finalized(_chosen_choice: UpgradeChoice) -> void:
	hide()


func _on_reroll_button_pressed() -> void:
	EventBus.upgrade_reroll_requested.emit()

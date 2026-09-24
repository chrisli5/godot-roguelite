class_name UpgradeCard
extends PanelContainer

@export_group("Internal UI References")
@export var title_label: Label
@export var description_label: Label
@export var target_tag_label: Label

var current_choice: UpgradeChoice
var disabled: bool = false


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)


func populate_display_data(choice: UpgradeChoice) -> void:
	if not is_instance_valid(choice): 
		return
		
	current_choice = choice
	
	if is_instance_valid(title_label):
		title_label.text = choice.display_name
		
	if is_instance_valid(description_label):
		description_label.text = choice.description
		
	if is_instance_valid(target_tag_label):
		target_tag_label.text = "Modifies: " + choice.target_display_name
	
	
func select_card() -> void:
	if is_instance_valid(current_choice):
		disabled = true
		EventBus.upgrade_selected.emit(current_choice)


func _on_gui_input(event: InputEvent) -> void:
	if disabled:
		return
	
	if event.is_action_pressed("mouse_button_left"):
		select_card()
		get_viewport().set_input_as_handled()
	
	
func _on_mouse_entered() -> void:
	if disabled:
		return

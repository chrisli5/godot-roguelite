class_name MainMenuUI
extends Control

@export_group("Internal Node Panel References")
@export var options_panel: Control

@export_group("Menu Button Mappings")
@export var start_button: Button
@export var start_action: MenuActionType

@export_group("Options Configuration")
@export var options_button: Button
@export var options_action: MenuActionType

@export_group("Quit Configuration")
@export var quit_button: Button


func _ready() -> void:
	if is_instance_valid(options_panel):
		options_panel.hide() # Hidden by default
	_bind_button_actions()


func _bind_button_actions() -> void:
	if is_instance_valid(start_button) and is_instance_valid(start_action):
		start_button.pressed.connect(_on_action_triggered.bind(start_action))
		
	if is_instance_valid(options_button) and is_instance_valid(options_action):
		options_button.pressed.connect(_on_action_triggered.bind(options_action))
		
	if is_instance_valid(quit_button):
		if OS.has_feature("web"):
			quit_button.hide()
		else:
			quit_button.pressed.connect(_on_quit_pressed)

## Centralized routing parser handling click sequences blindly based on injected rules
func _on_action_triggered(action: MenuActionType) -> void:
	if not is_instance_valid(action): 
		return

	match action.intent:
		MenuActionType.ActionIntent.LOAD_SCENE:
			if not action.target_scene_id.is_empty():
				EventBus.scene_change_requested.emit(action.target_scene_id)
				
		MenuActionType.ActionIntent.TOGGLE_OPTIONS_PANEL:
			if is_instance_valid(options_panel):
				options_panel.visible = not options_panel.visible
				
		MenuActionType.ActionIntent.QUIT_GAME:
			_on_quit_pressed()

func _on_quit_pressed() -> void:
	get_tree().quit()

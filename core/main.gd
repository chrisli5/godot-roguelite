class_name Main
extends Node

@export_group("Core Components")
@export var transition_manager: SceneTransitionManager

@export_group("Layout Containers")
@export var scene_container: Node

@export_group("Boot Configuration")
@export var initial_scene_key: String = "main_menu"


func _ready() -> void:
	if is_instance_valid(transition_manager) and is_instance_valid(scene_container):
		transition_manager.initialize_context(scene_container)
		
		if not initial_scene_key.is_empty():
			transition_manager.transition_to_scene.call_deferred(initial_scene_key)
	else:
		push_error("Main Core: Configuration dependency components missing or unassigned in the Inspector.")

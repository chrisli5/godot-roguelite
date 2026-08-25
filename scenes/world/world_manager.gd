class_name WorldManager
extends Node2D

enum ContainerType { ENTITIES, PROJECTILES, PICKUPS }

@export_group("Configuration")
@export var map_profile: MapProfile

@export_group("Layer Containers")
@export var entities_container: Node2D
@export var projectiles_container: Node2D
@export var pickups_container: Node2D


func _ready() -> void:
	EventBus.spawn_requested.connect(_on_spawn_requested)
	_instantiate_level_terrain()
	#_run_automated_test_clear_clock()


func _run_automated_test_clear_clock() -> void:
	print("[TEST] Welcome to ", map_profile.level_name, ". Auto-clearing room in 3 seconds...")
	
	# Create a temporary runtime scene timer
	var test_timer = get_tree().create_timer(3.0)
	await test_timer.timeout
	
	print("[TEST] Room objectives complete! Notifying MapGenerator...")
	# Emit the macro completion signal back up to the persistent managers
	EventBus.room_completion_confirmed.emit()


func _instantiate_level_terrain() -> void:
	if not is_instance_valid(map_profile) or map_profile.tilemap_scene_path.is_empty():
		push_error("WorldManager: Missing MapProfile configuration.")
		return

	var map_resource = load(map_profile.tilemap_scene_path)
	if map_resource:
		var tilemap_instance = map_resource.instantiate()
		add_child(tilemap_instance)
		move_child(tilemap_instance, 0) 


func _on_spawn_requested(node_to_spawn: Node2D, container_type: ContainerType) -> void:
	if not is_instance_valid(node_to_spawn): return
	
	match container_type:
		ContainerType.PROJECTILES:
			if is_instance_valid(projectiles_container):
				projectiles_container.add_child(node_to_spawn)
		ContainerType.ENTITIES:
			if is_instance_valid(entities_container):
				entities_container.add_child(node_to_spawn)
		ContainerType.PICKUPS:
			if is_instance_valid(pickups_container):
				pickups_container.add_child(node_to_spawn)

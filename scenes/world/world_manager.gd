class_name WorldManager
extends Node2D

@export_group("Configuration")
@export var map_profile: MapProfile
@export var player_spawner: PlayerSpawner

@export_group("Layer Containers")
@export var entities_container: Node2D
@export var projectiles_container: Node2D
@export var pickups_container: Node2D


func _ready() -> void:
	EventBus.spawn_requested.connect(_on_spawn_requested)
	if is_instance_valid(player_spawner):
		player_spawner.spawn_player_character()


func initialize_world_settings(new_map_profile: MapProfile) -> void:
	map_profile = new_map_profile
	_instantiate_level_terrain()


func _instantiate_level_terrain() -> void:
	if not is_instance_valid(map_profile) or map_profile.tilemap_scene_path.is_empty():
		push_error("WorldManager: Missing MapProfile configuration.")
		return

	var map_resource = load(map_profile.tilemap_scene_path)
	if map_resource:
		var tilemap_instance = map_resource.instantiate()
		add_child(tilemap_instance)
		move_child(tilemap_instance, 0) 


func _on_spawn_requested(node_to_spawn: Node2D) -> void:
	if not is_instance_valid(node_to_spawn): 
		return

	if node_to_spawn is Entity:
		if is_instance_valid(entities_container):
			entities_container.add_child(node_to_spawn)
			return

	elif node_to_spawn is CombatVolume:
		if is_instance_valid(projectiles_container):
			projectiles_container.add_child(node_to_spawn)
			return

	elif node_to_spawn is XPGem or node_to_spawn.has_node("ExperiencePickupComponent"):
		if is_instance_valid(pickups_container):
			pickups_container.add_child(node_to_spawn)
			return

	push_warning("[WORLD MANAGER] Unclassified node '%s' spawned. Mounting to fallback root node." % node_to_spawn.name)
	add_child(node_to_spawn)

class_name PlayerSpawner
extends Marker2D

@export_group("Player Configuration")
@export var player_scene: PackedScene

func spawn_player_character() -> void:
	if not is_instance_valid(player_scene):
		push_error("PlayerSpawner: Player Scene is unassigned in the Inspector.")
		return
		
	# 1. Instantiate the dynamic Player actor from disk data
	var player_instance = player_scene.instantiate()
	
	if player_instance is Node2D:
		# 2. Set the player's initial position to match this spawner's spatial coordinates
		player_instance.global_position = global_position
		
		# 3. Flashing the node into the global highway stream instead of hacking parent node calls
		EventBus.spawn_requested.emit(player_instance)
		
	# 4. Self-destruct to ensure zero node-bloat once its job is finished
	queue_free()

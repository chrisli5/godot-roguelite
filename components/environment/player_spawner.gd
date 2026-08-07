# res://components/environment/player_spawner.gd
class_name PlayerSpawner
extends Marker2D


@export_group("Player Configuration")
## Drag res://scenes/player/player.tscn into this slot in the Inspector panel
@export var player_scene: PackedScene


func _ready() -> void:
	_spawn_player_character()

func _spawn_player_character() -> void:
	if not is_instance_valid(player_scene):
		push_error("PlayerSpawner: Player Scene is unassigned in the Inspector.")
		return
		
	# 1. Instantiate the dynamic Player actor from disk data
	var player_instance = player_scene.instantiate()
	
	if player_instance is CharacterBody2D or player_instance is Node2D:
		# 2. Set the player's initial position to match this spawner's spatial coordinates
		player_instance.global_position = global_position
		
		# 3. Append the player cleanly to the parent container layout branch (EntitiesContainer)
		get_parent().call_deferred("add_child", player_instance)
	# 4. Self-destruct to ensure zero node-bloat once its job is finished
	queue_free()

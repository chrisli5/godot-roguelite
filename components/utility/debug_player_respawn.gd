# res://components/utility/debug_player_respawn.gd
class_name DebugPlayerRespawn
extends Node

## DEBUG ONLY. Press F3 to tear down the live player and spawn a fresh one.
## This runs the same capture and restore path a room change uses, so run persistence
## can be tested before the room-to-room loop is finished.


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_respawn_player()


func _respawn_player() -> void:
	var player := instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(player):
		return

	var scene_path := player.scene_file_path
	if scene_path.is_empty():
		push_error("DebugPlayerRespawn: Player has no scene_file_path to re-instantiate.")
		return

	var data := player.entity_data
	var spawn_position := player.global_position

	# Freeing the player triggers its capture step (Player._exit_tree)
	player.queue_free()
	await get_tree().process_frame

	var fresh := (load(scene_path) as PackedScene).instantiate() as Player
	fresh.initialize_entity(data)
	fresh.global_position = spawn_position
	EventBus.spawn_requested.emit(fresh)
	print("[DEBUG] Player respawned. Run state restored from RunSession.")

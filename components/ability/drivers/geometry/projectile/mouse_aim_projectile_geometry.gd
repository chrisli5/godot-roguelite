class_name MouseAimProjectileGeometry
extends ProjectileGeometry

func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	var player_spawn_pos: Vector2 = query_results.get("origin", Vector2.ZERO)
	var player = instance_from_id(EventBus.active_player_instance_id)
	
	if not is_instance_valid(player):
		return

	var mouse_target_pos: Vector2 = player.get_global_mouse_position()
	var fire_direction := (mouse_target_pos - player_spawn_pos).normalized()
	if fire_direction == Vector2.ZERO:
		fire_direction = Vector2.RIGHT # Safe fallback default

	# 4. Prepare the customized payload structure using parent utility helper
	var payload := _prepare_custom_payload(0, final_payload)
	
	# 5. Invoke the shared multi-shot fan / scatter loop engine helper
	# The projectiles physically leave the player's core and fly toward the mouse!
	_spawn_scatter_projectiles(player_spawn_pos, fire_direction, 0, payload)
	
	delivery_finished.emit()


func requires_spatial_query() -> bool:
	return false

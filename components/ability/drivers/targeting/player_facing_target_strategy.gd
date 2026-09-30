class_name PlayerFacingTargetStrategy
extends TargetingStrategy


func get_targeting_data(global_origin: Vector2, query_radius: float, _max_targets: int = 1) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	
	var player: Player = instance_from_id(EventBus.active_player_instance_id)
	if not is_instance_valid(player):
		results.append({
			"direction": Vector2.RIGHT,
			"target_id": 0,
			"target_position": global_origin + (Vector2.RIGHT * query_radius)
		})
		return results

	var facing_direction: Vector2 = player.velocity.normalized()
	if facing_direction == Vector2.ZERO:
		facing_direction = Vector2.RIGHT

	var active_range = query_radius if query_radius > 0.0 else 150.0
	var projected_coordinate: Vector2 = global_origin + (facing_direction * active_range)

	results.append({
		"direction": facing_direction,
		"target_id": 0,
		"target_position": projected_coordinate
	})

	return results

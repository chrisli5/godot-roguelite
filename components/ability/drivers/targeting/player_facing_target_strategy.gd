class_name PlayerFacingTargetStrategy
extends TargetingStrategy


func get_targeting_data(_global_origin: Vector2, _query_radius: float, _max_targets: int = 1) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	
	var player: Player = instance_from_id(EventBus.active_player_instance_id)
	if not is_instance_valid(player):
		results.append({
			"direction": Vector2.RIGHT,
			"target_id": 0
			})
		return results

	var facing_direction: Vector2 = player.velocity.normalized()
	if facing_direction == Vector2.ZERO:
		facing_direction = Vector2.RIGHT

	results.append({
		"direction": facing_direction,
		"target_id": 0 # Facing strategies carry zero tracked entity target IDs
		})

	return results

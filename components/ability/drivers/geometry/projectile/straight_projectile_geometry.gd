class_name StraightProjectileGeometry
extends ProjectileGeometry

func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	var origin: Vector2 = query_results.get("origin", Vector2.ZERO)
	var target_direction := Vector2.RIGHT
	
	var player = instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(player):
		target_direction = player.velocity.normalized() if player.velocity != Vector2.ZERO else Vector2.RIGHT

	var payload := _prepare_custom_payload(0, final_payload)
	_spawn_scatter_projectiles(origin, target_direction, 0, payload)
	
	delivery_finished.emit()


func requires_spatial_query() -> bool:
	return false

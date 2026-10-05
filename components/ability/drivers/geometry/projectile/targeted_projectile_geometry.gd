# res://components/ability/drivers/geometry/targeted_projectile_geometry.gd
class_name TargetedProjectileGeometry
extends ProjectileGeometry

## Strictly handles target extraction, validation tracking, and payload injection 
## before passing launch parameters back to the shared multi-shot scatter helper.
func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	var origin: Vector2 = query_results.get("origin", Vector2.ZERO)	
	var hit_nodes: Array = query_results.get("hit_nodes", [])
	if hit_nodes.is_empty():
		delivery_finished.emit()
		return

	var nearest_enemy: HurtboxComponent = hit_nodes[0]
	var fire_direction := (nearest_enemy.global_position - origin).normalized()
	if fire_direction == Vector2.ZERO:
		fire_direction = Vector2.RIGHT

	var tracking_id := nearest_enemy.get_instance_id()
	var payload := _prepare_custom_payload(tracking_id, final_payload)
	
	# 6. Invoke the shared multi-shot split / scatter fan loop engine helper
	_spawn_scatter_projectiles(origin, fire_direction, tracking_id, payload)

	delivery_finished.emit()
